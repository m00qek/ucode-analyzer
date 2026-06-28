import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable, nodeAtOffset } from 'ucode_language_server.positions';

// Collect all identifier nodes with matching text from the tree.
function collectIdentifiers(node, name, source, result) {
	if (ts.nodeType(node) === 'identifier' && ts.text(node, source) === name)
		push(result, node);
	let count = ts.childCount(node);
	for (let i = 0; i < count; i++)
		collectIdentifiers(ts.child(node, i), name, source, result);
}

export function references(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	if (ts.nodeType(node) !== 'identifier') return null;

	let name      = ts.text(node, doc.text);
	let found     = [];
	let lineTable = buildLineTable(doc.text);

	collectIdentifiers(root, name, doc.text, found);

	return map(found, (n) => {
		let start = offsetToPosition(doc.text, lineTable, ts.startByte(n));
		let end   = offsetToPosition(doc.text, lineTable, ts.endByte(n));
		return { uri, range: { start, end } };
	});
};
