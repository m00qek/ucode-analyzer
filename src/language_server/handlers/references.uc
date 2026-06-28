import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'language_server.positions';
import { referencesOf } from 'language_server.scope_references';

export function references(uri, doc, position, includeDeclaration) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset, includeDeclaration);
	if (!nodes) return null;

	let lineTable = buildLineTable(doc.text);
	return map(nodes, (n) => {
		let start = offsetToPosition(doc.text, lineTable, ts.startByte(n));
		let end   = offsetToPosition(doc.text, lineTable, ts.endByte(n));
		return { uri, range: { start, end } };
	});
};
