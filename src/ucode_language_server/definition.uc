import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'ucode_language_server.positions';
import * as dag from 'ucode_language_server.dag';
import * as fs from 'fs';

// Walk to the deepest named node containing offset.
function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
}

// Return an LSP Location object for byte offset inside uri.
function location(uri, text, byteOffset) {
	let lineTable = buildLineTable(text);
	let pos = offsetToPosition(text, lineTable, byteOffset);
	return { uri, range: { start: pos, end: pos } };
}

// If name is a named import into uri, return the Location of its definition.
function importedDefinition(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let exps = dag.exportsOf(imp.resolvedUri);
		if (!exps) continue;
		for (let j = 0; j < length(exps); j++) {
			if (exps[j].name !== name) continue;
			// Read the file to compute the position.
			let path = substr(imp.resolvedUri, length('file://'));
			let text = fs.readfile(path);
			if (!text) return null;
			// Find the byte offset of the export in that file.
			let parser = ts.newParser(ts.ucode());
			let tree = ts.parse(parser, text);
			let root = ts.rootNode(tree);
			for (let k = 0; k < ts.namedChildCount(root); k++) {
				let stmt = ts.namedChild(root, k);
				if (ts.nodeType(stmt) !== 'export_statement') continue;
				let decl = ts.namedChild(stmt, 0);
				if (!decl) continue;
				let nameNode = findExportName(decl, name, text);
				if (nameNode)
					return location(imp.resolvedUri, text, ts.startByte(nameNode));
			}
			return null;
		}
	}
	return null;
}

// Extract the identifier matching name from a function_declaration or
// lexical_declaration node. Returns the identifier node or null.
function findExportName(decl, name, text) {
	let dt = ts.nodeType(decl);
	if (dt === 'function_declaration') {
		let nameNode = ts.namedChild(decl, 0);
		if (nameNode && ts.text(nameNode, text) === name) return nameNode;
	} else if (dt === 'lexical_declaration') {
		for (let i = 0; i < ts.namedChildCount(decl); i++) {
			let vd = ts.namedChild(decl, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode && ts.text(nameNode, text) === name) return nameNode;
		}
	}
	return null;
}

// Find the first let/const/function declaration of name in the current file.
function localDefinition(uri, doc, name) {
	let root = ts.rootNode(doc.tree);
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		let nt = ts.nodeType(stmt);

		if (nt === 'lexical_declaration') {
			for (let j = 0; j < ts.namedChildCount(stmt); j++) {
				let vd = ts.namedChild(stmt, j);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nameNode = ts.childByField(vd, 'name');
				if (nameNode && ts.text(nameNode, doc.text) === name)
					return location(uri, doc.text, ts.startByte(nameNode));
			}
		} else if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(stmt, 0);
			if (nameNode && ts.text(nameNode, doc.text) === name)
				return location(uri, doc.text, ts.startByte(nameNode));
		} else if (nt === 'export_statement') {
			let decl = ts.namedChild(stmt, 0);
			if (!decl) continue;
			let nameNode = findExportName(decl, name, doc.text);
			if (nameNode)
				return location(uri, doc.text, ts.startByte(nameNode));
		}
	}
	return null;
}

export function definition(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	if (ts.nodeType(node) !== 'identifier') return null;

	let name = ts.text(node, doc.text);

	// Named import → jump to the exporting file.
	let imp = importedDefinition(uri, name);
	if (imp) return imp;

	// Local declaration.
	return localDefinition(uri, doc, name);
};
