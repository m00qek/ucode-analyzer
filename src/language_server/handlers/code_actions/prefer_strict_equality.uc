import * as ts from 'tree_sitter';
import { positionToOffset } from 'code_analysis.positions';

function nodeAt(node, offset) {
	if (ts.startByte(node) > offset || offset >= ts.endByte(node)) return null;
	let result = node;
	for (let i = 0; i < ts.childCount(node); i++) {
		let deeper = nodeAt(ts.child(node, i), offset);
		if (deeper) result = deeper;
	}
	return result;
}

export function actionsFor(uri, doc, diagnostics) {
	let root    = ts.rootNode(doc.tree);
	let actions = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'prefer-strict-equality') continue;

		let offset = positionToOffset(doc.text, doc.lineTable, diag.range.start);
		let op     = nodeAt(root, offset);
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
