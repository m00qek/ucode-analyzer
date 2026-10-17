import * as ts from 'tree_sitter';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { identifierOccurrences } from 'ucode_analyzer.code_analysis.ast_text';

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

export function unusedImports(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;

	let bindings = [];
	collectImportBindings(root, source, bindings);
	if (!length(bindings)) return [];

	// Import clauses are intentionally included so their bytes match a binding's
	// declByte; any reference outside the clause has a different byte.
	let refs = identifierOccurrences(root, source, false);

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
				source:   'ucode-analyzer',
				code:     'unused-import',
				message:  sprintf("'%s' is imported but never used", b.name),
			});
	}
	return diags;
};
