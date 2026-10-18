import * as ts from 'tree_sitter';
import * as fs from 'fs';
import { parseDoc } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { buildLineTable, offsetToPosition, docBeforeMap } from 'ucode_analyzer.code_analysis.positions';
import { topLevelStatements, importStmtSpecifier, importBindings, importRemoteName } from 'ucode_analyzer.code_analysis.mode';
import { stringLiteralText, namedNonComments, declarators, paramNodes, isComment } from 'ucode_analyzer.code_analysis.ast_text';


function dotToSlash(s) {
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		out += (c === '.') ? '/' : c;
	}
	return out;
}

// The parameters of a function node as [{ name, rest }], or null when the node
// is not a function. They type an export whose doc comment names none.
function paramsOf(fn, text) {
	let t = fn ? ts.nodeType(fn) : null;
	if (t !== 'function_declaration' && t !== 'function_expression' && t !== 'arrow_function')
		return null;
	return map(paramNodes(fn), (p) => ({ name: ts.text(p.node, text), rest: p.rest }));
}

// The type of a number, string or boolean literal (as the inferrer types it),
// or null. Only for consts: a `let` the module reassigns would be mistyped.
function literalType(node, text) {
	let t = node ? ts.nodeType(node) : null;
	if (t === 'string' || t === 'template_string') return { kind: 'primitive', name: 'string' };
	if (t === 'true' || t === 'false') return { kind: 'primitive', name: 'boolean' };
	if (t !== 'number') return null;
	let digits = ts.text(node, text);
	let float = !match(digits, /^0[xXbBoO]/) && match(digits, /[.eE]/);
	return { kind: 'primitive', name: float ? 'float' : 'int' };
}

function isConstDecl(decl) {
	for (let j = 0; j < ts.childCount(decl); j++) {
		let child = ts.child(decl, j);
		if (!ts.isNamed(child) && ts.nodeType(child) === 'const') return true;
	}
	return false;
}

// Build a { name -> { kind, doc, startByte, params, valueType } } index of every top-level
// declaration in one pass. Callers that need to resolve many names (an
// export_clause, or a legacy return object's identifier fields) share one
// index instead of re-walking the tree per name — that re-walk was O(fields²)
// on large modules (fw4.uc's 88-field return object ≈ 67ms per reindex).
// First declaration of a name wins, matching the old first-match scan.
// docOf(stmt) is the text of the /** */ before a top-level statement, or null.
function buildDeclIndex(root, text, docOf) {
	let index = {};
	for (let stmt in topLevelStatements(root)) {
		let nt = ts.nodeType(stmt);
		if (nt === 'function_declaration') {
			let nameNode = ts.childByField(stmt, 'name');
			if (!nameNode) continue;
			let name = ts.text(nameNode, text);
			if (exists(index, name)) continue;
			let docText = docOf(stmt);
			index[name] = { kind: 'function', doc: docText ? parseDoc(docText) : null, startByte: ts.startByte(nameNode),
			                params: paramsOf(stmt, text), valueType: null };
		} else if (nt === 'lexical_declaration') {
			let isConst = isConstDecl(stmt);
			for (let vd in declarators(stmt)) {
				let nameNode = ts.childByField(vd, 'name');
				if (!nameNode) continue;
				let name = ts.text(nameNode, text);
				if (exists(index, name)) continue;
				let init = ts.childByField(vd, 'value');
				let it = init ? ts.nodeType(init) : null;
				let kind = (it === 'arrow_function' || it === 'function_expression') ? 'function' : 'let';
				let docText = docOf(stmt);
				index[name] = { kind, doc: docText ? parseDoc(docText) : null, startByte: ts.startByte(nameNode),
				                params: paramsOf(init, text), valueType: isConst ? literalType(init, text) : null };
			}
		}
	}
	return index;
}

// Return { kind, doc, startByte, params, valueType } for the local declaration
// of name, from a prebuilt declIndex. startByte is the byte offset of the name
// identifier node, or null if the name has no top-level declaration.
function localDeclInfo(index, name) {
	return exists(index, name) ? index[name]
		: { kind: 'let', doc: null, startByte: null, params: null, valueType: null };
}

// Walk an object literal and return property descriptors { name, kind, doc, properties }.
// For function-expression values the preceding /** */ inside the object is used.
// For identifier values the local declaration (function or const) is resolved.
// For nested object literals the function recurses, populating properties.
function extractObjectProperties(objectNode, index, text, pos) {
	let props = [];
	// One pass for all field docs; per-field docBefore would be O(fields²).
	let docMap = docBeforeMap(objectNode, text);
	for (let i = 0; i < ts.namedChildCount(objectNode); i++) {
		let pair = ts.namedChild(objectNode, i);
		if (ts.nodeType(pair) === 'shorthand_property_identifier') {
			let name = ts.text(pair, text);
			let info = localDeclInfo(index, name);
			push(props, { name, kind: info.kind, doc: info.doc, properties: null,
			              params: info.params, valueType: info.valueType,
			              position: pos ? pos(ts.startByte(pair)) : null });
			continue;
		}
		if (ts.nodeType(pair) !== 'pair') continue;
		let keyNode = ts.childByField(pair, 'key');
		if (!keyNode) continue;
		let kt = ts.nodeType(keyNode);
		if (kt !== 'property_identifier' && kt !== 'identifier') continue;
		let name = ts.text(keyNode, text);
		let valNode = ts.childByField(pair, 'value');
		let vtype = valNode ? ts.nodeType(valNode) : null;
		let kind, doc, properties, params = null, valueType = null;
		if (vtype === 'function_expression' || vtype === 'arrow_function') {
			kind       = 'function';
			let docText = docMap[ts.startByte(pair)];
			doc        = docText ? parseDoc(docText) : null;
			properties = null;
			params     = paramsOf(valNode, text);
		} else if (vtype === 'identifier') {
			let info   = localDeclInfo(index, ts.text(valNode, text));
			kind       = info.kind;
			doc        = info.doc;
			properties = null;
			params     = info.params;
			valueType  = info.valueType;
		} else if (vtype === 'object') {
			kind       = 'object';
			doc        = null;
			properties = extractObjectProperties(valNode, index, text, pos);
		} else {
			kind       = 'value';
			doc        = null;
			properties = null;
		}
		push(props, { name, kind, doc, properties, params, valueType,
		              position: pos ? pos(ts.startByte(keyNode)) : null });
	}
	return props;
}

export function extractExports(text, tree) {
	let result = [];
	let root = ts.rootNode(tree);
	let lineTable = buildLineTable(text);

	function pos(startByte) {
		return offsetToPosition(text, lineTable, startByte);
	}

	// The docs of all top-level statements, from one pass over the root's
	// children: per-statement docBefore rescans them, O(statements²).
	let _docs = null;
	function docOf(stmt) {
		if (_docs === null) _docs = docBeforeMap(root, text);
		return _docs[ts.startByte(stmt)];
	}

	// The declaration index is only needed for `export { ... }` clauses and the
	// legacy return object; pure `export function`/`export let` files never touch
	// it. Build it at most once, on first use.
	let _declIndex = null;
	function declIndex() {
		if (_declIndex === null) _declIndex = buildDeclIndex(root, text, docOf);
		return _declIndex;
	}

	// What an exported value refers to: `alias.member` (re-export), a local
	// name, or an object literal's properties.
	function initRefs(init) {
		let refs = { memberRef: null, localRef: null, properties: null };
		let t = init ? ts.nodeType(init) : null;
		if (t === 'member_expression') {
			let obj  = ts.childByField(init, 'object');
			let prop = ts.childByField(init, 'property');
			if (obj && ts.nodeType(obj) === 'identifier' &&
			    prop && ts.nodeType(prop) === 'property_identifier')
				refs.memberRef = { alias: ts.text(obj, text), member: ts.text(prop, text) };
		} else if (t === 'identifier') {
			refs.localRef = ts.text(init, text);
		} else if (t === 'object') {
			refs.properties = extractObjectProperties(init, declIndex(), text, pos);
		}
		return refs;
	}

	// The first top-level `return {…}` is the legacy module export object (see
	// note below). Captured during the single statement pass and processed after
	// the ES exports so those take precedence.
	let sawReturn  = false;
	let returnObj  = null;

	for (let stmt in topLevelStatements(root)) {
		let stmtType = ts.nodeType(stmt);
		if (stmtType === 'return_statement') {
			if (!sawReturn) {
				sawReturn = true;
				let val = namedNonComments(stmt)[0];
				if (val && ts.nodeType(val) === 'object') returnObj = val;
			}
			continue;
		}
		if (stmtType !== 'export_statement') continue;

		let docText = docOf(stmt);
		let doc = docText ? parseDoc(docText) : null;

		let value = ts.childByField(stmt, 'value');
		while (value && ts.nodeType(value) === 'parenthesized_expression')
			value = namedNonComments(value)[0];
		if (value) {
			let t = ts.nodeType(value);
			let refs = initRefs(value);
			let isFn = (t === 'function_expression' || t === 'arrow_function');
			push(result, { name: 'default', kind: isFn ? 'function' : 'const', doc,
			               memberRef: refs.memberRef, localRef: refs.localRef, properties: refs.properties,
			               params: paramsOf(value, text), valueType: literalType(value, text),
			               position: pos(ts.startByte(value)) });
			continue;
		}

		let decl = ts.childByField(stmt, 'declaration') ?? ts.childByField(stmt, 'clause');
		if (!decl) continue;

		let declType = ts.nodeType(decl);

		if (declType === 'function_declaration') {
			let nameNode = ts.childByField(decl, 'name');
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				push(result, { name: ts.text(nameNode, text), kind: 'function', doc,
				               params: paramsOf(decl, text), position: pos(ts.startByte(nameNode)) });

		} else if (declType === 'lexical_declaration') {
			let kind = isConstDecl(decl) ? 'const' : 'let';
			for (let varDecl in declarators(decl)) {
				let nameNode = ts.childByField(varDecl, 'name');
				if (!nameNode || ts.nodeType(nameNode) !== 'identifier') continue;
				let value = ts.childByField(varDecl, 'value');
				let refs = initRefs(value);
				push(result, { name: ts.text(nameNode, text), kind, doc,
				               memberRef: refs.memberRef, localRef: refs.localRef, properties: refs.properties,
				               params: paramsOf(value, text),
				               valueType: kind === 'const' ? literalType(value, text) : null,
				               position: pos(ts.startByte(nameNode)) });
			}
		} else if (declType === 'export_clause') {
			for (let j = 0; j < ts.namedChildCount(decl); j++) {
				let spec = ts.namedChild(decl, j);
				if (ts.nodeType(spec) !== 'export_specifier') continue;
				// The exported name is the alias (`{ local as name }`), else the name
				// itself; `default` (`{ local as default }`) is a named node too.
				let localNameNode = ts.childByField(spec, 'name');
				let nameNode = ts.childByField(spec, 'alias') ?? localNameNode;
				let nt = nameNode ? ts.nodeType(nameNode) : null;
				if (nt !== 'identifier' && nt !== 'default' && nt !== 'string') continue;
				let name = (nt === 'string') ? stringLiteralText(nameNode, text) : ts.text(nameNode, text);
				// Look up the local binding, so kind/doc reflect the actual declaration.
				let localName = localNameNode ? ts.text(localNameNode, text) : name;
				let info = localDeclInfo(declIndex(), localName);
				let position = (info.startByte !== null) ? pos(info.startByte) : null;
				push(result, { name, kind: info.kind, doc: info.doc, params: info.params,
				               valueType: info.valueType, position, local: localName });
			}
		}
	}

	// Legacy module pattern: a top-level `return { ... }` is the module's export
	// object — ucode's classic require() shape, used throughout OpenWrt (fw4,
	// luci) instead of ES `export`. Surface each field as an export so a
	// require()'d member (`fw4.read_state`) resolves for hover, definition and
	// type inference exactly like a namespace member. ES `export`s take
	// precedence: they are pushed above, so a name already present is skipped.
	// Only the first top-level return is the module value (captured above).
	if (returnObj) {
		let seen = {};
		for (let i = 0; i < length(result); i++) seen[result[i].name] = true;
		for (let prop in extractObjectProperties(returnObj, declIndex(), text, pos))
			// `legacy`: reachable through require() only; importing it fails.
			if (!seen[prop.name]) { prop.legacy = true; push(result, prop); }
	}

	return result;
};

export function extractImports(text, tree) {
	let result = [];
	let root = ts.rootNode(tree);

	for (let stmt in topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		let specifier = importStmtSpecifier(stmt, text);
		if (!specifier) continue;

		let b = importBindings(stmt);

		if (b.namespaceAlias)
			push(result, { specifier, symbols: ['*'], alias: ts.text(b.namespaceAlias, text),
			               resolvedUri: null });

		if (length(b.specifiers) > 0) {
			let symbols = [];
			let renames = {};
			for (let s in b.specifiers) {
				let remoteName = importRemoteName(s, text);
				let localName  = ts.text(s.localNode, text);
				push(symbols, localName);
				if (localName !== remoteName) renames[localName] = remoteName;
			}
			push(result, { specifier, symbols, renames, alias: null, resolvedUri: null });
		}
	}

	return result;
};

// Resolves a module specifier to a file:// URI using the given library paths.
// libraryPaths are absolute paths. workspaceDir is the workspace root (used
// to resolve relative libraryPaths).
export function resolveModule(specifier, libraryPaths, workspaceDir) {
	let slashForm = dotToSlash(specifier) + '.uc';
	let dotForm   = specifier + '.uc';
	let declForm  = dotToSlash(specifier) + '.d.uc';

	for (let libPath in libraryPaths) {
		let absLib = (substr(libPath, 0, 1) === '/') ? libPath : workspaceDir + '/' + libPath;
		let candidates = [
			absLib + '/' + slashForm,
			absLib + '/' + dotForm,
			absLib + '/' + declForm,
			absLib + '/declarations/' + declForm,
		];

		for (let candidate in candidates) {
			let s = fs.stat(candidate);
			if (s && (s.type === 'file' || s.type === 'regular'))
				return 'file://' + candidate;
		}
	}

	return null;
};

// Return the parsed JSDoc for the first /** */ comment in the file, if it has
// a description. This is the module-level doc (e.g. @module utest.assert).
// Extract the ordered version list from a "// Versions: v1, v2, ..." header comment.
// Returns an array of trimmed version strings, or null if the comment is absent.
export function extractVersions(text) {
	let head = substr(text, 0, 512);
	let m = match(head, /\/\/ Versions: ([^\n]+)/);
	if (!m) return null;
	let parts = [];
	for (let v in split(m[1], /,\s*/)) {
		let t = trim(v);
		if (length(t) > 0) push(parts, t);
	}
	return length(parts) > 0 ? parts : null;
};

export function extractModuleDoc(text, tree) {
	let root = ts.rootNode(tree);
	let children = ts.namedChildren(root);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		let ct = ts.nodeType(c);
		if (ct !== 'comment' && ct !== 'doc_comment') break;
		if (ct !== 'doc_comment') continue;
		let raw = ts.text(c, text);
		// Directly before a statement, it documents that statement. It is the
		// module's when it says @module, or another comment or a blank line
		// follows it.
		let next = children[i + 1];
		if (next && !isComment(next) && index(raw, '@module') < 0 &&
		    !match(substr(text, ts.endByte(c), ts.startByte(next) - ts.endByte(c)), /\n[ \t]*\n/))
			return null;
		let doc = parseDoc(raw);
		if (doc.description) return doc;
		break;
	}
	return null;
};

// The @typedefs of the file's /** */ comments, as [{ name, type, params }].
export function extractTypedefs(text, tree) {
	let out = [];
	if (index(text, '@typedef') < 0) return out;
	let root = ts.rootNode(tree);
	let children = ts.namedChildren(root);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.nodeType(c) !== 'doc_comment') continue;
		let raw = ts.text(c, text);
		if (index(raw, '@typedef') < 0) continue;
		let doc = parseDoc(raw);
		if (doc.typedef && doc.typedef.name && doc.typedef.type)
			push(out, { name: doc.typedef.name, type: doc.typedef.type, params: doc.template });
	}
	return out;
};
