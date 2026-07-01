import * as ts from 'tree_sitter';
import * as mode from 'code_analysis.mode';
import { rangeOf } from 'code_analysis.positions';

let SEVERITY_HINT = 4;

// Collect import-introduced local names: named specifiers and namespace aliases.
// Each entry: { name, declByte, nameNode }
function collectImportBindings(root, source, out) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		for (let n in mode.importBindingNodes(stmt))
			if (ts.nodeType(n) === 'identifier')
				push(out, { name: ts.text(n, source), declByte: ts.startByte(n), nameNode: n });
	}
}

// Build a set of byte offsets for every identifier in the tree.
// Import clauses are intentionally included so their bytes match declByte;
// any reference outside will have a different byte.
function buildRefIndex(root, source) {
	let idx = {};
	function walk(node) {
		let nt = ts.nodeType(node);
		if (nt === 'identifier' || nt === 'shorthand_property_identifier') {
			let name = ts.text(node, source);
			if (!exists(idx, name)) idx[name] = [];
			push(idx[name], ts.startByte(node));
		}
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i));
	}
	walk(root);
	return idx;
}

export function unusedImports(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;

	let bindings = [];
	collectImportBindings(root, source, bindings);

	let refs = buildRefIndex(root, source);

	let diags = [];
	for (let i = 0; i < length(bindings); i++) {
		let b = bindings[i];
		let allBytes = refs[b.name] ?? [];
		let hasUse = false;
		for (let j = 0; j < length(allBytes); j++) {
			if (allBytes[j] !== b.declByte) { hasUse = true; break; }
		}
		if (!hasUse)
			push(diags, {
				range:    rangeOf(source, lineTable, b.nameNode),
				severity: SEVERITY_HINT,
				source:   'ucode-ls',
				code:     'unused-import',
				message:  sprintf("'%s' is imported but never used", b.name),
			});
	}
	return diags;
};
