import * as ts from 'tree_sitter';
import * as mode from 'code_analysis.mode';
import { rangeOf } from 'code_analysis.positions';
import * as dag from 'code_analysis.dag.dag';

let SEVERITY_ERROR = 1;

// Build a set of exported names for a resolved module URI.
// Triggers a disk index if the module has not been loaded yet.
function exportNames(resolvedUri) {
	if (!dag.exportsOf(resolvedUri)) dag.addFromDisk(resolvedUri);
	let exps = dag.exportsOf(resolvedUri);
	if (!exps) return null;
	let names = {};
	for (let i = 0; i < length(exps); i++)
		names[exps[i].name] = true;
	return names;
}

export function unknownImportSymbols(uri, doc) {
	let imps = dag.importsOf(uri);
	if (!imps) return [];

	let lineTable = doc.lineTable;
	let diags = [];
	let root = ts.rootNode(doc.tree);

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		let specifier = mode.importStmtSpecifier(stmt, doc.text);
		if (!specifier) continue;

		// Find the matching import record and its resolved URI.
		let resolvedUri = null;
		for (let j = 0; j < length(imps); j++) {
			if (imps[j].specifier === specifier) { resolvedUri = imps[j].resolvedUri; break; }
		}
		if (!resolvedUri) continue;  // unresolvable module — already reported by unknownImports

		// Only named imports can name a symbol that doesn't exist; a namespace
		// import takes everything.
		let specs = mode.importBindings(stmt).specifiers;
		if (length(specs) === 0) continue;
		let exported = exportNames(resolvedUri);
		if (!exported) continue;

		for (let s in specs) {
			if (!s.remoteNode) continue;
			let remoteName = ts.text(s.remoteNode, doc.text);
			if (!exists(exported, remoteName))
				push(diags, {
					range:    rangeOf(doc.text, lineTable, s.remoteNode),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'unknown-import-symbol',
					message:  sprintf("Module has no export named '%s'", remoteName),
				});
		}
	}

	return diags;
};
