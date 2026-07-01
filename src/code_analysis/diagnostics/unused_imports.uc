import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'code_analysis.positions';

let SEVERITY_HINT = 4;

// Collect import-introduced local names: named specifiers and namespace aliases.
// Each entry: { name, declByte, nameNode }
function collectImportBindings(root, source, out) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		for (let j = 0; j < ts.namedChildCount(stmt); j++) {
			let clause = ts.namedChild(stmt, j);
			if (ts.nodeType(clause) !== 'import_clause') continue;

			for (let k = 0; k < ts.namedChildCount(clause); k++) {
				let part = ts.namedChild(clause, k);
				let pnt  = ts.nodeType(part);

				if (pnt === 'namespace_import') {
					let alias = ts.namedChild(part, 0);
					if (alias && ts.nodeType(alias) === 'identifier')
						push(out, { name: ts.text(alias, source), declByte: ts.startByte(alias), nameNode: alias });

				} else if (pnt === 'named_imports') {
					for (let m = 0; m < ts.namedChildCount(part); m++) {
						let spec = ts.namedChild(part, m);
						if (ts.nodeType(spec) !== 'import_specifier') continue;
						let cnt = ts.namedChildCount(spec);
						if (cnt === 0) continue;
						// Last named child is the local name (alias if present, original otherwise).
						let localNode = ts.namedChild(spec, cnt - 1);
						if (localNode && ts.nodeType(localNode) === 'identifier')
							push(out, { name: ts.text(localNode, source), declByte: ts.startByte(localNode), nameNode: localNode });
					}
				}
			}
		}
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
	let lineTable = buildLineTable(source);

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
