import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable, nodeAtOffset } from 'language_server.positions';
import * as dag from 'language_server.dag.dag';
import * as fs from 'fs';
import { inferNode, globalUri } from 'language_server.types.inferrer';
import { scopeAtOffset } from 'language_server.types.scope_walk';
import * as type_registry from 'language_server.types.registry';

let _parser = ts.newParser(ts.ucode());

// Return an LSP Location object for byte offset inside uri.
function location(uri, text, byteOffset) {
	let lineTable = buildLineTable(text);
	let pos = offsetToPosition(text, lineTable, byteOffset);
	return { uri, range: { start: pos, end: pos } };
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

// Recursively search node (which must contain offset) for a function scope
// whose formal_parameters contain name. Returns the Location of the parameter
// identifier in the innermost matching scope, or null.
function walkForParam(node, uri, doc, name, offset) {
	if (ts.startByte(node) > offset || offset >= ts.endByte(node)) return null;

	// Recurse first so the innermost scope wins.
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let res = walkForParam(ts.namedChild(node, i), uri, doc, name, offset);
		if (res) return res;
	}

	let nt = ts.nodeType(node);
	if (nt !== 'function_declaration' && nt !== 'arrow_function' && nt !== 'function_expression')
		return null;

	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let child = ts.namedChild(node, i);
		if (ts.nodeType(child) !== 'formal_parameters') continue;
		for (let j = 0; j < ts.namedChildCount(child); j++) {
			let param = ts.namedChild(child, j);
			if (ts.nodeType(param) === 'identifier' && ts.text(param, doc.text) === name)
				return location(uri, doc.text, ts.startByte(param));
		}
		break;
	}
	return null;
}

// If name is a namespace import alias (import * as name), return a Location
// pointing to the top of the imported module file.
function namespaceDef(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias === name && imp.resolvedUri)
			return { uri: imp.resolvedUri, range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } } };
	}
	return null;
}

// Resolve a member name in a type to a file Location.
// Handles direct record types (with sourceUri+position from exportType/inferObject)
// and typedef refs (via the type registry).
function locationOfMember(type, propName, depth) {
	if (!depth) depth = 0;
	if (depth > 5 || !type) return null;
	if (type.kind === 'record') {
		if (!type.sourceUri) return null;
		for (let i = 0; i < length(type.fields); i++) {
			let f = type.fields[i];
			if (f.name !== propName) continue;
			let pos = f.position ?? { line: 0, character: 0 };
			return { uri: type.sourceUri, range: { start: pos, end: pos } };
		}
		return null;
	}
	if (type.kind === 'ref') {
		let def = type_registry.lookup(type.name);
		if (!def) return null;
		return locationOfMember(def.type, propName, depth + 1);
	}
	return null;
}

// Return a Location for name in resolvedUri, using the DAG-cached position when
// available to avoid re-parsing. Falls back to a full disk re-parse otherwise.
function resolveExportDefinition(resolvedUri, name) {
	let exp = dag.resolveExport(resolvedUri, name);
	if (exp && exp.position)
		return { uri: resolvedUri, range: { start: exp.position, end: exp.position } };
	// Fallback: re-parse from disk (handles export_clause or unindexed files).
	let path = substr(resolvedUri, length('file://'));
	let text = fs.readfile(path);
	if (!text) return null;
	let tree = ts.parse(_parser, text);
	let root = ts.rootNode(tree);
	for (let k = 0; k < ts.namedChildCount(root); k++) {
		let stmt = ts.namedChild(root, k);
		if (ts.nodeType(stmt) !== 'export_statement') continue;
		let decl = ts.namedChild(stmt, 0);
		if (!decl) continue;
		let nameNode = findExportName(decl, name, text);
		if (nameNode)
			return location(resolvedUri, text, ts.startByte(nameNode));
	}
	let doc = { uri: resolvedUri, text, tree, lineTable: buildLineTable(text) };
	return localDefinition(resolvedUri, doc, name);
}

// If cursor is on a property_identifier inside a member_expression, resolve
// via namespace import DAG or scope-based type inference.
// Handles both simple `obj.prop` (objNode is identifier) and chained `a.b.prop`
// (objNode is a member_expression — inferNode recurses through the chain).
function memberExprDef(uri, doc, memberExpr, propName, offset) {
	let objNode = ts.namedChild(memberExpr, 0);
	if (!objNode) return null;

	// Namespace import fast path: only applies when the object is a direct alias.
	if (ts.nodeType(objNode) === 'identifier') {
		let objName = ts.text(objNode, doc.text);
		let imps = dag.importsOf(uri);
		if (imps) {
			for (let i = 0; i < length(imps); i++) {
				let imp = imps[i];
				if (imp.alias !== objName || !imp.resolvedUri) continue;
				let loc = dag.resolveExportLocation(imp.resolvedUri, propName);
				let exp = dag.resolveExport(loc.uri, loc.name);
				if (!exp) return null;
				return resolveExportDefinition(loc.uri, loc.name);
			}
		}
	}

	// Scope-based: infer the type of the object.
	// inferNode handles identifiers and chained member_expressions alike.
	let scope = scopeAtOffset(doc.scopeMap, offset);
	let objType = inferNode(objNode, doc.text, uri, scope, 0);
	if (objType && objType.kind === 'nullable') objType = objType.inner;

	// Module type (e.g. named import whose value is a whole module)
	if (objType && objType.kind === 'module') {
		let r = dag.resolveMember(objType.path, propName);
		if (r) return resolveExportDefinition(r.uri, r.name);
	}

	// Record type: find member using stored position and sourceUri
	return locationOfMember(objType, propName);
}

// If name is a named import into uri, return the Location of its definition.
function importedDefinition(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let loc = dag.resolveExportLocation(imp.resolvedUri, remoteName);
		let exp = dag.resolveExport(loc.uri, loc.name);
		if (!exp) continue;
		return resolveExportDefinition(loc.uri, loc.name);
	}
	return null;
}

export function definition(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	let nt = ts.nodeType(node);

	// Member expression property (e.g. `mod.fn` — cursor on `fn`)
	if (nt === 'property_identifier') {
		let parent = ts.parent(node);
		if (parent && ts.nodeType(parent) === 'member_expression')
			return memberExprDef(uri, doc, parent, ts.text(node, doc.text), offset);
		return null;
	}

	if (nt !== 'identifier') return null;

	let name = ts.text(node, doc.text);

	// Named import → jump to the exporting file.
	let imp = importedDefinition(uri, name);
	if (imp) return imp;

	// Namespace import alias → jump to the module file.
	let ns = namespaceDef(uri, name);
	if (ns) return ns;

	// Function parameter in the innermost enclosing scope.
	let param = walkForParam(root, uri, doc, name, offset);
	if (param) return param;

	// Top-level declaration.
	let local = localDefinition(uri, doc, name);
	if (local) return local;

	// Builtin: jump to its declaration in global.d.uc.
	let gUri = globalUri();
	return gUri ? resolveExportDefinition(gUri, name) : null;
};
