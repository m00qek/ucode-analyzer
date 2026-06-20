import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { buildScope } from 'ucode_language_server.inferrer';
import { typeToString } from 'ucode_language_server.doc_parser';
import * as dag from 'ucode_language_server.dag';

// LSP CompletionItemKind constants
let KIND_FUNCTION = 3;
let KIND_VARIABLE  = 6;
let KIND_MODULE    = 9;

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
					if (ts.nodeType(c) !== 'string') continue;
					for (let k = 0; k < ts.childCount(c); k++) {
						let f = ts.child(c, k);
						if (ts.nodeType(f) === 'string_fragment')
							return ts.text(f, source);
					}
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

// Format a type for a completion item's detail field.
function detail(exp) {
	if (!exp.doc) return null;
	if (exp.doc.returns && exp.doc.returns.type)
		return typeToString(exp.doc.returns.type);
	return null;
}

// Completion items for all exports of a resolved module URI.
function exportsOfModule(resolvedUri) {
	let exps = dag.exportsOf(resolvedUri);
	if (!exps) return [];
	return map(exps, (exp) => ({
		label: exp.name,
		kind: (exp.kind === 'function') ? KIND_FUNCTION : KIND_VARIABLE,
		detail: detail(exp),
		documentation: (exp.doc && exp.doc.description) ? exp.doc.description : null,
	}));
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
				push(items, {
					label: localName,
					kind: (exp.kind === 'function') ? KIND_FUNCTION : KIND_VARIABLE,
					detail: detail(exp),
				});
			}
		}
	}
	return items;
}

// Completion items from the lexical scope at offset.
function scopeItems(uri, doc, offset) {
	let scope = buildScope(uri, doc.text, doc.tree, offset);
	let items = [];
	let seen = {};
	let s = scope;
	while (s) {
		for (let name in keys(s.bindings)) {
			if (seen[name]) continue;
			seen[name] = true;
			let t = s.bindings[name];
			push(items, {
				label: name,
				kind: (t && t.kind === 'function') ? KIND_FUNCTION : KIND_VARIABLE,
				detail: t ? typeToString(t) : null,
			});
		}
		s = s.parent;
	}
	return items;
}

export function completion(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);

	// Special case: cursor is inside an import_statement — offer module exports.
	let specifier = importContext(root, doc.text, offset);
	if (specifier !== null) {
		// Find the import that matches (any resolved import whose specifier matches).
		let imps = dag.importsOf(uri);
		if (imps) {
			for (let i = 0; i < length(imps); i++) {
				if (imps[i].specifier === specifier && imps[i].resolvedUri)
					return exportsOfModule(imps[i].resolvedUri);
			}
		}
		return [];
	}

	// General: scope locals + imported symbols.
	let items = scopeItems(uri, doc, offset);
	let imported = importedItems(uri);
	for (let i = 0; i < length(imported); i++) push(items, imported[i]);
	return items;
};
