import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';

// Returns the deepest named node whose byte range contains offset.
function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);

	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);

		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}

	return node;
};

export function hover(doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);

	if (offset >= ts.endByte(root))
		return null;

	let node = nodeAtOffset(root, offset);

	return {
		contents: {
			kind: 'markdown',
			value: sprintf('```ucode\n%s\n```\n\n*node:* `%s`',
				ts.text(node, doc.text),
				ts.nodeType(node)),
		},
	};
};
