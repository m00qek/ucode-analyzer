import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { inferNode, buildScope, stdlibUri } from 'ucode_language_server.types.inferrer';
import { typeToString } from 'ucode_language_server.types.doc_parser';
import * as dag from 'ucode_language_server.dag.dag';

function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
}

// Find the parsed JSDoc for a builtin in stdlib.d.uc.
function builtinDoc(name) {
	let uri = stdlibUri();
	if (!uri) return null;
	let exps = dag.exportsOf(uri);
	if (!exps) return null;
	for (let i = 0; i < length(exps); i++)
		if (exps[i].name === name && exps[i].doc)
			return exps[i].doc;
	return null;
}

// Find the parsed JSDoc for a named import resolved via the DAG.
function importedDoc(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let exp = dag.resolveExport(imp.resolvedUri, remoteName);
		if (exp && exp.doc) return exp.doc;
	}
	return null;
}

// Find the parsed JSDoc for an export in the same file.
function localDoc(uri, name) {
	let exps = dag.exportsOf(uri);
	if (!exps) return null;
	for (let i = 0; i < length(exps); i++) {
		let exp = exps[i];
		if (exp.name === name && exp.doc) return exp.doc;
	}
	return null;
}

function renderDoc(expDoc, md) {
	if (expDoc.description) md += '\n\n' + expDoc.description;
	for (let i = 0; i < length(expDoc.examples); i++)
		md += '\n\n**Example:**\n```ucode\n' + expDoc.examples[i] + '\n```';
	return md;
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
		let expDoc = importedDoc(doc.uri, label) ?? builtinDoc(label) ?? localDoc(doc.uri, label);
		if (expDoc) md = renderDoc(expDoc, md);
	}

	return {
		contents: { kind: 'markdown', value: md },
	};
};
