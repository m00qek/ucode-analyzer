import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { inferNode, buildScope } from 'ucode_language_server.inferrer';
import { typeToString } from 'ucode_language_server.doc_parser';
import * as dag from 'ucode_language_server.dag';

function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
}

// Find the JSDoc description for a named import resolved via the DAG.
function importedDescription(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let exps = dag.exportsOf(imp.resolvedUri);
		if (!exps) continue;
		for (let j = 0; j < length(exps); j++) {
			let exp = exps[j];
			if (exp.name === name && exp.doc && exp.doc.description)
				return exp.doc.description;
		}
	}
	return null;
}

export function hover(doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	let scope = buildScope(doc.uri, doc.text, doc.tree, ts.startByte(node));
	let type = inferNode(node, doc.text, doc.uri, scope, 0);

	if (type.kind === 'unknown') return null;

	let label = ts.text(node, doc.text);
	let typeStr = typeToString(type);
	let md = sprintf('```ucode\n%s: %s\n```', label, typeStr);

	if (ts.nodeType(node) === 'identifier') {
		let desc = importedDescription(doc.uri, label);
		if (desc) md += '\n\n' + desc;
	}

	return {
		contents: { kind: 'markdown', value: md },
	};
};
