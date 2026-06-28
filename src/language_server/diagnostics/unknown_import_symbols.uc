import * as ts from 'tree_sitter';
import { offsetToPosition, buildLineTable } from 'language_server.positions';
import * as dag from 'language_server.dag.dag';

let SEVERITY_ERROR = 1;

function rangeOf(text, lineTable, node) {
	let start = offsetToPosition(text, lineTable, ts.startByte(node));
	let end   = offsetToPosition(text, lineTable, ts.endByte(node));
	return { start, end };
}

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

// Walk the import_specifier nodes inside a named_imports clause and report
// any remote name that is not in the module's export set.
function checkNamedImports(clause, doc, lineTable, resolvedUri, diags) {
	let exported = exportNames(resolvedUri);
	if (!exported) return;

	for (let i = 0; i < ts.namedChildCount(clause); i++) {
		let spec = ts.namedChild(clause, i);
		if (ts.nodeType(spec) !== 'import_specifier') continue;

		// For `{ remote as local }` the first child is the remote name.
		// For `{ name }` the single child is both remote and local.
		let remoteNode = ts.namedChild(spec, 0);
		if (!remoteNode) continue;
		let remoteName = ts.text(remoteNode, doc.text);

		if (!exists(exported, remoteName))
			push(diags, {
				range:    rangeOf(doc.text, lineTable, remoteNode),
				severity: SEVERITY_ERROR,
				message:  sprintf("Module has no export named '%s'", remoteName),
			});
	}
}

export function unknownImportSymbols(uri, doc) {
	let imps = dag.importsOf(uri);
	if (!imps) return [];

	let lineTable = buildLineTable(doc.text);
	let diags = [];
	let root = ts.rootNode(doc.tree);

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		// Find which import record this statement corresponds to.
		// Match by extracting the specifier string from the AST.
		let specifier = null;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let c = ts.child(stmt, j);
			if (ts.nodeType(c) !== 'string') continue;
			for (let k = 0; k < ts.childCount(c); k++) {
				let f = ts.child(c, k);
				if (ts.nodeType(f) === 'string_fragment') { specifier = ts.text(f, doc.text); break; }
			}
			break;
		}
		if (!specifier) continue;

		// Find the matching import record and its resolved URI.
		let resolvedUri = null;
		for (let j = 0; j < length(imps); j++) {
			if (imps[j].specifier === specifier) { resolvedUri = imps[j].resolvedUri; break; }
		}
		if (!resolvedUri) continue;  // unresolvable module — already reported by unknownImports

		// Only named imports can have wrong symbol names; namespace imports take everything.
		for (let j = 0; j < ts.namedChildCount(stmt); j++) {
			let clause = ts.namedChild(stmt, j);
			if (ts.nodeType(clause) !== 'import_clause') continue;
			for (let k = 0; k < ts.namedChildCount(clause); k++) {
				let part = ts.namedChild(clause, k);
				if (ts.nodeType(part) === 'named_imports')
					checkNamedImports(part, doc, lineTable, resolvedUri, diags);
			}
		}
	}

	return diags;
};
