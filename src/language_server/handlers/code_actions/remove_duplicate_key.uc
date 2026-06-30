import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition } from 'language_server.positions';

function nodeAt(node, offset) {
	if (ts.startByte(node) > offset || offset >= ts.endByte(node)) return null;
	let result = node;
	for (let i = 0; i < ts.childCount(node); i++) {
		let child = nodeAt(ts.child(node, i), offset);
		if (child) result = child;
	}
	return result;
}

function ancestor(node, type) {
	let p = ts.parent(node);
	while (p) {
		if (ts.nodeType(p) === type) return p;
		p = ts.parent(p);
	}
	return null;
}

export function actionsFor(uri, doc, diagnostics) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let actions   = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'duplicate-key') continue;

		let offset  = positionToOffset(source, lineTable, diag.range.start);
		let keyNode = nodeAt(root, offset);
		if (!keyNode) continue;

		let pairNode = ancestor(keyNode, 'pair');
		if (!pairNode) continue;

		let objNode = ancestor(pairNode, 'object');
		if (!objNode) continue;

		// Collect all pair named children of the object.
		let pairs = [];
		for (let i = 0; i < ts.namedChildCount(objNode); i++) {
			let c = ts.namedChild(objNode, i);
			if (ts.nodeType(c) === 'pair') push(pairs, c);
		}

		let pairStart = ts.startByte(pairNode);
		let idx = -1;
		for (let i = 0; i < length(pairs); i++) {
			if (ts.startByte(pairs[i]) === pairStart) { idx = i; break; }
		}
		if (idx < 0) continue;

		let n = length(pairs);
		let start, end;
		if (idx < n - 1) {
			// Not last: eat from start of this pair to start of next (absorbs trailing ", " or ",\n...")
			start = ts.startByte(pairs[idx]);
			end   = ts.startByte(pairs[idx + 1]);
		} else {
			// Last: eat from end of previous pair to end of this pair (absorbs preceding ",\n..." or ", ")
			start = ts.endByte(pairs[idx - 1]);
			end   = ts.endByte(pairs[idx]);
		}

		let keyText = ts.text(keyNode, source);

		push(actions, {
			title:       sprintf("Remove duplicate key '%s'", keyText),
			kind:        'quickfix',
			diagnostics: [diag],
			isPreferred: true,
			edit: {
				changes: {
					[uri]: [{
						range: {
							start: offsetToPosition(source, lineTable, start),
							end:   offsetToPosition(source, lineTable, end),
						},
						newText: '',
					}],
				},
			},
		});
	}

	return actions;
};
