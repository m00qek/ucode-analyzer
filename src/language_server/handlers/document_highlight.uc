import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition } from 'code_analysis.positions';
import { referencesOf } from 'language_server.scope_references';

export function documentHighlight(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset, true);
	if (!nodes) return null;

	return map(nodes, (n) => ({
		range: {
			start: offsetToPosition(doc.text, doc.lineTable, ts.startByte(n)),
			end:   offsetToPosition(doc.text, doc.lineTable, ts.endByte(n)),
		},
		kind: 1,
	}));
};
