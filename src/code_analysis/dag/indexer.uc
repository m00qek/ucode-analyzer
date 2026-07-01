import * as ts from 'tree_sitter';
import * as fs from 'fs';
import { parseDoc } from 'code_analysis.types.doc_parser';
import * as type_registry from 'code_analysis.types.registry';
import { buildLineTable, offsetToPosition, docBefore } from 'code_analysis.positions';
import { topLevelStatements } from 'code_analysis.mode';


function dotToSlash(s) {
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		out += (c === '.') ? '/' : c;
	}
	return out;
}

// Return { kind, doc, startByte } for the local declaration of name.
// startByte is the byte offset of the name identifier node, or null if not found.
function localDeclInfo(root, text, name) {
	for (let stmt in topLevelStatements(root)) {
		let nt = ts.nodeType(stmt);
		if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(stmt, 0);
			if (nameNode && ts.text(nameNode, text) === name) {
				let docText = docBefore(stmt, root, text);
				return { kind: 'function', doc: docText ? parseDoc(docText) : null, startByte: ts.startByte(nameNode) };
			}
		} else if (nt === 'lexical_declaration') {
			for (let j = 0; j < ts.namedChildCount(stmt); j++) {
				let vd = ts.namedChild(stmt, j);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nameNode = ts.namedChild(vd, 0);
				if (!nameNode || ts.text(nameNode, text) !== name) continue;
				let init = ts.childByField(vd, 'value');
				let it = init ? ts.nodeType(init) : null;
				let kind = (it === 'arrow_function' || it === 'function_expression') ? 'function' : 'let';
				let docText = docBefore(stmt, root, text);
				return { kind, doc: docText ? parseDoc(docText) : null, startByte: ts.startByte(nameNode) };
			}
		}
	}
	return { kind: 'let', doc: null, startByte: null };
}

// Extracts the module specifier string from an import_statement node.
function importSpecifier(stmt, text) {
	for (let i = 0; i < ts.childCount(stmt); i++) {
		let child = ts.child(stmt, i);
		if (ts.nodeType(child) !== 'string') continue;
		for (let j = 0; j < ts.childCount(child); j++) {
			let frag = ts.child(child, j);
			if (ts.nodeType(frag) === 'string_fragment')
				return ts.text(frag, text);
		}
	}
	return null;
}

// Walk an object literal and return property descriptors { name, kind, doc, properties }.
// For function-expression values the preceding /** */ inside the object is used.
// For identifier values the local declaration (function or const) is resolved.
// For nested object literals the function recurses, populating properties.
function extractObjectProperties(objectNode, root, text, pos) {
	let props = [];
	for (let i = 0; i < ts.namedChildCount(objectNode); i++) {
		let pair = ts.namedChild(objectNode, i);
		if (ts.nodeType(pair) === 'shorthand_property_identifier') {
			let name = ts.text(pair, text);
			let info = localDeclInfo(root, text, name);
			push(props, { name, kind: info.kind, doc: info.doc, properties: null,
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
		let kind, doc, properties;
		if (vtype === 'function_expression' || vtype === 'arrow_function') {
			kind       = 'function';
			let docText = docBefore(pair, objectNode, text);
			doc        = docText ? parseDoc(docText) : null;
			properties = null;
		} else if (vtype === 'identifier') {
			let info   = localDeclInfo(root, text, ts.text(valNode, text));
			kind       = info.kind;
			doc        = info.doc;
			properties = null;
		} else if (vtype === 'object') {
			kind       = 'object';
			doc        = null;
			properties = extractObjectProperties(valNode, root, text, pos);
		} else {
			kind       = 'value';
			doc        = null;
			properties = null;
		}
		push(props, { name, kind, doc, properties, position: pos ? pos(ts.startByte(keyNode)) : null });
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

	for (let stmt in topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'export_statement') continue;

		let decl = ts.namedChild(stmt, 0);
		if (!decl) continue;

		let declType = ts.nodeType(decl);

		let docText = docBefore(stmt, root, text);
		let doc = docText ? parseDoc(docText) : null;

		if (declType === 'function_declaration') {
			let nameNode = ts.namedChild(decl, 0);
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				push(result, { name: ts.text(nameNode, text), kind: 'function', doc,
				               position: pos(ts.startByte(nameNode)) });

		} else if (declType === 'lexical_declaration') {
			let kind = 'let';
			for (let j = 0; j < ts.childCount(decl); j++) {
				let child = ts.child(decl, j);
				if (!ts.isNamed(child) && ts.nodeType(child) === 'const') {
					kind = 'const';
					break;
				}
			}
			for (let j = 0; j < ts.namedChildCount(decl); j++) {
				let varDecl = ts.namedChild(decl, j);
				if (ts.nodeType(varDecl) !== 'variable_declarator') continue;
				let nameNode = ts.namedChild(varDecl, 0);
				if (!nameNode || ts.nodeType(nameNode) !== 'identifier') continue;
				let init = ts.childByField(varDecl, 'value');
				let memberRef  = null;
				let localRef   = null;
				let properties = null;
				if (init && ts.nodeType(init) === 'member_expression') {
					let obj  = ts.namedChild(init, 0);
					let prop = ts.namedChild(init, 1);
					if (obj  && ts.nodeType(obj) === 'identifier' &&
					    prop && (ts.nodeType(prop) === 'property_identifier' ||
					             ts.nodeType(prop) === 'identifier'))
						memberRef = { alias: ts.text(obj, text), member: ts.text(prop, text) };
				} else if (init && ts.nodeType(init) === 'identifier') {
					localRef = ts.text(init, text);
				} else if (init && ts.nodeType(init) === 'object') {
					properties = extractObjectProperties(init, root, text, pos);
				}
				push(result, { name: ts.text(nameNode, text), kind, doc, memberRef, localRef, properties,
				               position: pos(ts.startByte(nameNode)) });
			}
		} else if (declType === 'export_clause') {
			for (let j = 0; j < ts.namedChildCount(decl); j++) {
				let spec = ts.namedChild(decl, j);
				if (ts.nodeType(spec) !== 'export_specifier') continue;
				// last named child is the exported name (handles both `{ name }` and `{ local as name }`)
				let count = ts.namedChildCount(spec);
				let nameNode = ts.namedChild(spec, count - 1);
				if (!nameNode || ts.nodeType(nameNode) !== 'identifier') continue;
				let name = ts.text(nameNode, text);
				// For `{ local as alias }` the local (original) name is the first child; use it
				// for the declaration lookup so kind/doc reflect the actual local binding.
				let localNameNode = (count > 1) ? ts.namedChild(spec, 0) : nameNode;
				let localName = localNameNode ? ts.text(localNameNode, text) : name;
				let info = localDeclInfo(root, text, localName);
				let position = (info.startByte !== null) ? pos(info.startByte) : null;
				push(result, { name, kind: info.kind, doc: info.doc, position });
			}
		}
	}

	// Legacy module pattern: a top-level `return { ... }` is the module's export
	// object — ucode's classic require() shape, used throughout OpenWrt (fw4,
	// luci) instead of ES `export`. Surface each field as an export so a
	// require()'d member (`fw4.read_state`) resolves for hover, definition and
	// type inference exactly like a namespace member. ES `export`s take
	// precedence: they are pushed above and resolveExport returns the first match
	// by name. Only the first top-level return is the module value.
	for (let stmt in topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'return_statement') continue;
		let val = ts.namedChild(stmt, 0);
		if (val && ts.nodeType(val) === 'object') {
			// A file mixing `export` and a top-level return object: the ES export
			// wins (pushed above), so don't emit a duplicate entry for the name.
			let seen = {};
			for (let i = 0; i < length(result); i++) seen[result[i].name] = true;
			for (let prop in extractObjectProperties(val, root, text, pos))
				if (!seen[prop.name]) push(result, prop);
		}
		break;
	}

	return result;
};

export function extractImports(text, tree) {
	let result = [];
	let root = ts.rootNode(tree);

	for (let stmt in topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		let specifier = importSpecifier(stmt, text);
		if (!specifier) continue;

		let clause = null;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let child = ts.child(stmt, j);
			if (ts.nodeType(child) === 'import_clause') { clause = child; break; }
		}
		if (!clause) continue;

		let clauseChild = ts.namedChild(clause, 0);
		if (!clauseChild) continue;

		let clauseType = ts.nodeType(clauseChild);

		if (clauseType === 'named_imports') {
			let symbols = [];
			let renames = {};
			for (let j = 0; j < ts.namedChildCount(clauseChild); j++) {
				let spec = ts.namedChild(clauseChild, j);
				if (ts.nodeType(spec) !== 'import_specifier') continue;
				let count = ts.namedChildCount(spec);
				let remoteNode = ts.namedChild(spec, 0);
				if (!remoteNode) continue;
				let remoteName = ts.text(remoteNode, text);
				// For `{ remote as local }`, the alias (local binding) is the last named child.
				let localName = remoteName;
				if (count > 1) {
					let localNode = ts.namedChild(spec, count - 1);
					if (localNode) localName = ts.text(localNode, text);
				}
				push(symbols, localName);
				if (localName !== remoteName) renames[localName] = remoteName;
			}
			push(result, { specifier, symbols, renames, alias: null, resolvedUri: null });

		} else if (clauseType === 'namespace_import') {
			let alias = null;
			let count = ts.namedChildCount(clauseChild);
			if (count > 0) {
				let last = ts.namedChild(clauseChild, count - 1);
				if (ts.nodeType(last) === 'identifier')
					alias = ts.text(last, text);
			}
			push(result, { specifier, symbols: ['*'], alias, resolvedUri: null });
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
		if (ts.nodeType(c) !== 'comment') break;
		let txt = ts.text(c, text);
		if (substr(txt, 0, 3) !== '/**') continue;
		let doc = parseDoc(txt);
		if (doc.description) return doc;
		break;
	}
	return null;
};

// Walk every /** */ comment in the file and register any @typedef it contains.
// Removes stale entries for this uri first so re-indexing stays consistent.
export function extractTypedefs(uri, text, tree) {
	type_registry.removeUri(uri);
	let root = ts.rootNode(tree);
	let children = ts.namedChildren(root);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.nodeType(c) !== 'comment') continue;
		let txt = ts.text(c, text);
		if (substr(txt, 0, 3) !== '/**') continue;
		let doc = parseDoc(txt);
		if (doc.typedef && doc.typedef.name && doc.typedef.type)
			type_registry.register(doc.typedef.name, doc.typedef.type, uri, doc.template);
	}
};
