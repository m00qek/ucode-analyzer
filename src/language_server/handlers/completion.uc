import * as ts from 'tree_sitter';
import { positionToOffset } from 'code_analysis.positions';
import { stringLiteralText } from 'code_analysis.ast_text';
import { inferNode } from 'code_analysis.types.inferrer';
import { scopeAtOffset } from 'code_analysis.types.scope_walk';
import { typeToString } from 'code_analysis.types.doc_parser';
import * as dag from 'code_analysis.dag.dag';
import * as type_registry from 'code_analysis.types.registry';
import * as platform from 'language_server.platform';

// LSP CompletionItemKind constants
let KIND_FUNCTION = 3;
let KIND_VARIABLE  = 6;
let KIND_MODULE    = 9;
let KIND_KEYWORD   = 14;

// All ucode keywords offered in non-member, non-import contexts.
let KEYWORDS = [
	'break', 'case', 'catch', 'const', 'continue', 'default', 'delete',
	'do', 'else', 'export', 'false', 'finally', 'for', 'function', 'if',
	'import', 'in', 'instanceof', 'let', 'null', 'return', 'switch',
	'throw', 'true', 'try', 'typeof', 'void', 'while',
];

// Walk the tree to find if offset falls inside an import_statement.
// Returns the specifier string (e.g. 'tree_sitter') or null if not in one.
function importContext(root, source, offset) {
	function findImport(node) {
		let count = ts.namedChildCount(node);
		for (let i = 0; i < count; i++) {
			let child = ts.namedChild(node, i);
			if (ts.startByte(child) > offset) break;
			if (ts.endByte(child) <= offset) continue;
			if (ts.nodeType(child) === 'import_statement') {
				for (let j = 0; j < ts.childCount(child); j++) {
					let c = ts.child(child, j);
					if (ts.nodeType(c) === 'string') return stringLiteralText(c, source);
				}
				return '';
			}
			let inner = findImport(child);
			if (inner !== null) return inner;
		}
		return null;
	}
	return findImport(root);
}

// Build a snippet string for a function completion.
// Uses type params when available, JSDoc params as fallback,
// or a bare $1 placeholder when param count is unknown.
function fnSnippet(label, fnType, docParams) {
	let names = [];
	if (fnType && fnType.kind === 'function' && length(fnType.params ?? []) > 0) {
		names = map(fnType.params, (p) => p.name ?? 'arg');
	} else if (docParams && length(docParams) > 0) {
		names = map(docParams, (p) => p.name ?? 'arg');
	}
	if (length(names) === 0) {
		// Known zero-param function → empty parens; unknown count → placeholder.
		return (fnType && fnType.kind === 'function') ? label + '()' : label + '($1)';
	}
	let parts = [];
	for (let i = 0; i < length(names); i++)
		push(parts, sprintf('${%d:%s}', i + 1, names[i]));
	return label + '(' + join(', ', parts) + ')';
}

// Format a type for a completion item's detail field.
function detail(exp) {
	if (!exp.doc) return null;
	if (exp.doc.returns && exp.doc.returns.type)
		return typeToString(exp.doc.returns.type);
	return null;
}

// Return the object-side node of the member_expression at offset, or null.
//
// Primary path: descend to the leaf, then walk up to a member_expression
// ancestor. Covers `obj.prop|` (cursor on property) and `obj.|` when the
// parser preserves the member_expression node.
//
// Fallback path: when the tree degrades (cursor right after a dot that the
// parser could not attach to a property), the character at offset-1 is '.'
// and there is no member_expression ancestor. In that case find the deepest
// named node that contains offset-2 (the last byte of the expression before
// the dot) and return it as the object. inferNode handles both plain
// identifiers and property_identifiers (the latter triggers inferMember).
function memberContext(root, source, offset) {
	function descend(node) {
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let child = ts.namedChild(node, i);
			if (ts.startByte(child) <= offset && offset <= ts.endByte(child))
				return descend(child);
		}
		return node;
	}
	let n = descend(root);
	while (n) {
		let nt = ts.nodeType(n);
		if (nt === 'member_expression') return ts.namedChild(n, 0);
		if (nt === 'program' || nt === 'statement_block' || nt === 'statement_list') break;
		n = ts.parent(n);
	}

	if (offset >= 2 && substr(source, offset - 1, 1) === '.') {
		function findAt(node, pos) {
			for (let i = 0; i < ts.namedChildCount(node); i++) {
				let child = ts.namedChild(node, i);
				if (ts.startByte(child) <= pos && pos < ts.endByte(child))
					return findAt(child, pos);
			}
			return node;
		}
		return findAt(root, offset - 2);
	}

	return null;
}

// Completion items for all exports of a resolved module URI.
// Lazy-indexes the module if not yet in the DAG.
// Hides the entire module if not installed; hides individual symbols not yet
// available in the installed version (based on @since).
function exportsOfModule(resolvedUri) {
	if (!dag.exportsOf(resolvedUri)) dag.addFromDisk(resolvedUri);
	let exps = dag.exportsOf(resolvedUri);
	if (!exps) return [];
	if (!platform.moduleAvailable(resolvedUri)) return [];
	let items = [];
	for (let i = 0; i < length(exps); i++) {
		let exp = exps[i];
		if (!platform.symbolAvailable(resolvedUri, exp.doc?.since)) continue;
		let r = dag.resolveExport(resolvedUri, exp.name) ?? exp;
		let isFn = (r.kind === 'function');
		let item = {
			label:         exp.name,
			kind:          isFn ? KIND_FUNCTION : KIND_VARIABLE,
			detail:        detail(r),
			documentation: (r.doc && r.doc.description) ? r.doc.description : null,
		};
		if (isFn) {
			item.insertText       = fnSnippet(exp.name, null, r.doc?.params);
			item.insertTextFormat = 2;
		}
		if (r.doc && r.doc.deprecated) item.tags = [1];
		push(items, item);
	}
	return items;
}

// Return completion items for all members of type.
// Dispatches on kind: module → DAG exports, record → fields, ref → registry,
// union → merged fields from all record members (first definition wins).
function membersOfType(type) {
	if (!type || type.kind === 'unknown') return [];
	if (type.kind === 'nullable') return membersOfType(type.inner);
	if (type.kind === 'union') {
		let seen = {};
		let items = [];
		for (let i = 0; i < length(type.members); i++) {
			for (let item in membersOfType(type.members[i])) {
				if (!seen[item.label]) {
					seen[item.label] = true;
					push(items, item);
				}
			}
		}
		return items;
	}
	if (type.kind === 'module') {
		let modUri = dag.resolveSpecifier(type.path);
		if (!modUri) return [];
		return exportsOfModule(modUri);
	}
	if (type.kind === 'record') {
		let items = [];
		for (let i = 0; i < length(type.fields); i++) {
			let f = type.fields[i];
			let isFn = (f.type && f.type.kind === 'function');
			let item = {
				label:         f.name,
				kind:          isFn ? KIND_FUNCTION : KIND_VARIABLE,
				detail:        f.type ? typeToString(f.type) : null,
				documentation: (f.doc && f.doc.description) ? f.doc.description : null,
			};
			if (isFn) {
				item.insertText       = fnSnippet(f.name, f.type, f.doc?.params);
				item.insertTextFormat = 2;
			}
			if (f.doc && f.doc.deprecated) item.tags = [1];
			push(items, item);
		}
		return items;
	}
	if (type.kind === 'ref') {
		let def = type_registry.lookup(type.name);
		if (def) return membersOfType(def.type);
	}
	return [];
}

// Completion items from all named imports visible in this file.
function importedItems(uri) {
	let imps = dag.importsOf(uri);
	if (!imps) return [];
	let items = [];
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri) continue;
		if (imp.alias) {
			// Namespace import: offer the alias itself as a MODULE item.
			push(items, { label: imp.alias, kind: KIND_MODULE, detail: imp.specifier });
		} else {
			// Named imports: offer each imported symbol under its local binding name.
			let exps = dag.exportsOf(imp.resolvedUri);
			if (!exps) {
				dag.addFromDisk(imp.resolvedUri);
				exps = dag.exportsOf(imp.resolvedUri);
			}
			if (!exps) continue;
			for (let j = 0; j < length(exps); j++) {
				let exp = exps[j];
				// Find the local name for this export, accounting for renames.
				let localName = null;
				for (let k = 0; k < length(imp.symbols); k++) {
					let sym = imp.symbols[k];
					let remote = (imp.renames && imp.renames[sym]) ?? sym;
					if (remote === exp.name) { localName = sym; break; }
				}
				if (localName === null) continue;
				let r = dag.resolveExport(imp.resolvedUri, exp.name) ?? exp;
				let isFn = (r.kind === 'function');
				let item = {
					label:         localName,
					kind:          isFn ? KIND_FUNCTION : KIND_VARIABLE,
					detail:        detail(r),
					documentation: (r.doc && r.doc.description) ? r.doc.description : null,
				};
				if (isFn) {
					item.insertText       = fnSnippet(localName, null, r.doc?.params);
					item.insertTextFormat = 2;
				}
				if (r.doc && r.doc.deprecated) item.tags = [1];
				push(items, item);
			}
		}
	}
	return items;
}

// Completion items from the lexical scope at offset.
function scopeItems(uri, doc, offset) {
	let scope = scopeAtOffset(doc.scopeMap, offset);
	let items = [];
	let seen = {};
	let s = scope;
	while (s) {
		for (let name in keys(s.bindings)) {
			if (seen[name]) continue;
			seen[name] = true;
			let t = s.bindings[name];
			let isFn = (t && t.kind === 'function');
			let item = {
				label:  name,
				kind:   isFn ? KIND_FUNCTION : KIND_VARIABLE,
				detail: t ? typeToString(t) : null,
			};
			if (isFn) {
				item.insertText       = fnSnippet(name, t, null);
				item.insertTextFormat = 2;
			}
			push(items, item);
		}
		s = s.parent;
	}
	return items;
}

export function completion(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);

	// Cursor is inside an import_statement — offer that module's exports.
	let specifier = importContext(root, doc.text, offset);
	if (specifier !== null) {
		let imps = dag.importsOf(uri);
		if (imps) {
			for (let i = 0; i < length(imps); i++) {
				if (imps[i].specifier === specifier && imps[i].resolvedUri)
					return exportsOfModule(imps[i].resolvedUri);
			}
		}
		return [];
	}

	// Cursor is after a '.' inside a member_expression — offer that type's members.
	let objNode = memberContext(root, doc.text, offset);
	if (objNode) {
		let scope = scopeAtOffset(doc.scopeMap, offset);
		let objType = inferNode(objNode, doc.text, uri, scope, 0);
		return membersOfType(objType);
	}

	// General: scope locals + imported symbols + language keywords.
	let items = scopeItems(uri, doc, offset);
	let imported = importedItems(uri);
	for (let i = 0; i < length(imported); i++) push(items, imported[i]);
	for (let i = 0; i < length(KEYWORDS); i++)
		push(items, { label: KEYWORDS[i], kind: KIND_KEYWORD });
	return items;
};
