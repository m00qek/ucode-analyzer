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

// Follow the full export chain for name in uri and return the original definition's doc.
// Covers both direct exports (with their own doc) and re-exports (localRef/memberRef chains).
function resolvedExportDoc(uri, name) {
	let exp = dag.resolveExport(uri, name);
	return (exp && exp.doc) ? exp.doc : null;
}

// Return the doc for a property_identifier node inside a member_expression.
// Handles two cases:
//   module type  — look up the member as a direct export of the module
//   record type  — look up the doc stored in the record field
function modulePropertyDoc(uri, propNode, source, scope) {
	let parent = ts.parent(propNode);
	if (!parent || ts.nodeType(parent) !== 'member_expression') return null;
	let objNode  = ts.namedChild(parent, 0);
	let propName = ts.text(propNode, source);
	let objType  = inferNode(objNode, source, uri, scope, 0);
	if (!objType) return null;
	if (objType.kind === 'module') {
		let modUri = dag.resolveSpecifier(objType.path);
		if (!modUri) return null;
		if (!dag.exportsOf(modUri)) dag.addFromDisk(modUri);
		let exp = dag.resolveExport(modUri, propName);
		return (exp && exp.doc) ? exp.doc : null;
	}
	if (objType.kind === 'record') {
		for (let i = 0; i < length(objType.fields); i++) {
			let f = objType.fields[i];
			if (f.name === propName && f.doc) return f.doc;
		}
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
		let expDoc = importedDoc(doc.uri, label) ?? resolvedExportDoc(doc.uri, label);
		if (!expDoc && type.kind === 'module') {
			let modUri = dag.resolveSpecifier(type.path);
			if (modUri) {
				if (!dag.exportsOf(modUri)) dag.addFromDisk(modUri);
				expDoc = dag.moduleDocOf(modUri);
			}
		}
		if (!expDoc && type.kind !== 'module') expDoc = builtinDoc(label);
		if (expDoc) md = renderDoc(expDoc, md);
	} else if (ts.nodeType(node) === 'property_identifier') {
		let expDoc = modulePropertyDoc(doc.uri, node, doc.text, scope);
		if (expDoc) md = renderDoc(expDoc, md);
	}

	return {
		contents: { kind: 'markdown', value: md },
	};
};
