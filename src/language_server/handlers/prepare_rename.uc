import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'language_server.positions';
import { referencesOf } from 'language_server.scope_references';

export function prepareRename(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset);
	if (!nodes) return null;

	let lineTable = buildLineTable(doc.text);
	// Find the specific identifier node the cursor is on.
	let cursorNode = null;
	for (let i = 0; i < length(nodes); i++) {
		let n = nodes[i];
		if (ts.startByte(n) <= offset && offset < ts.endByte(n)) {
			cursorNode = n;
			break;
		}
	}
	if (!cursorNode) return null;

	return {
		range: {
			start: offsetToPosition(doc.text, lineTable, ts.startByte(cursorNode)),
			end:   offsetToPosition(doc.text, lineTable, ts.endByte(cursorNode)),
		},
		placeholder: ts.text(cursorNode, doc.text),
	};
};
