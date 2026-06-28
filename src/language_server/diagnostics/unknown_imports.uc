import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';
import * as dag from 'language_server.dag.dag';

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
			let specifier = '';
			for (let k = 0; k < ts.childCount(c); k++) {
				let f = ts.child(c, k);
				if (ts.nodeType(f) === 'string_fragment') specifier = ts.text(f, doc.text);
			}
			if (unresolved[specifier] && !exists(reported, specifier)) {
				reported[specifier] = true;
				push(diags, {
					range: rangeOf(doc.text, lineTable, c),
					severity: SEVERITY_ERROR,
					message: sprintf("Cannot find module '%s'", specifier),
				});
			}
		}
	}
	return diags;
};
