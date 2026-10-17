import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { stringLiteralText } from 'ucode_analyzer.code_analysis.ast_text';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

export function unknownImports(uri, doc) {
	let imps = dag.importsOf(uri);
	if (!imps) return [];

	let unresolved = {};
	for (let i = 0; i < length(imps); i++)
		if (!imps[i].resolvedUri) unresolved[imps[i].specifier] = true;
	if (!length(keys(unresolved))) return [];

	let lineTable = doc.lineTable;
	let diags = [];
	let reported = {};
	let root = ts.rootNode(doc.tree);
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let c = ts.child(stmt, j);
			if (ts.nodeType(c) !== 'string') continue;
			let specifier = stringLiteralText(c, doc.text);
			if (unresolved[specifier] && !exists(reported, specifier)) {
				reported[specifier] = true;
				push(diags, diagnostic(rangeOf(doc.text, lineTable, c), Severity.ERROR, 'unknown-import',
					sprintf("Cannot find module '%s'", specifier)));
			}
		}
	}
	return diags;
};
