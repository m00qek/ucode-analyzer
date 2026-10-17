import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_analyzer.code_analysis.positions';

export function actionsFor(uri, doc, diagnostics) {
	let root    = ts.rootNode(doc.tree);
	let actions = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'prefer-strict-equality') continue;

		let offset = positionToOffset(doc.text, doc.lineTable, diag.range.start);
		let op     = ts.descendantAt(root, offset);
		if (!op) continue;

		let opType = ts.nodeType(op);
		let replacement;
		if (opType === '==')      replacement = '===';
		else if (opType === '!=') replacement = '!==';
		else continue;

		push(actions, {
			title:       sprintf("Replace '%s' with '%s'", opType, replacement),
			kind:        'quickfix',
			diagnostics: [diag],
			isPreferred: true,
			edit: {
				changes: { [uri]: [{ range: diag.range, newText: replacement }] },
			},
		});
	}

	return actions;
};
