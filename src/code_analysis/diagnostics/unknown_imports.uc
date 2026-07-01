import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'code_analysis.positions';
import { stringLiteralText } from 'code_analysis.ast_text';
import * as dag from 'code_analysis.dag.dag';

let SEVERITY_ERROR = 1;

export function unknownImports(uri, doc) {
	let imps = dag.importsOf(uri);
	if (!imps) return [];

	let unresolved = {};
	for (let i = 0; i < length(imps); i++)
		if (!imps[i].resolvedUri) unresolved[imps[i].specifier] = true;
	if (!length(keys(unresolved))) return [];

	let lineTable = buildLineTable(doc.text);
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
				push(diags, {
					range:    rangeOf(doc.text, lineTable, c),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'unknown-import',
					message:  sprintf("Cannot find module '%s'", specifier),
				});
			}
		}
	}
	return diags;
};
