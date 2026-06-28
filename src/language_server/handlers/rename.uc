import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'language_server.positions';
import { referencesOf } from 'language_server.scope_references';

export function rename(uri, doc, position, newName) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset);
	if (!nodes) return null;

	let lineTable = buildLineTable(doc.text);
	let edits = map(nodes, (n) => {
		let start = offsetToPosition(doc.text, lineTable, ts.startByte(n));
		let end   = offsetToPosition(doc.text, lineTable, ts.endByte(n));
		return { range: { start, end }, newText: newName };
	});

	return { changes: { [uri]: edits } };
};
