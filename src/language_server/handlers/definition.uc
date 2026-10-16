import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable, nodeAtOffset } from 'code_analysis.positions';
import { stringLiteralText } from 'code_analysis.ast_text';
import * as dag from 'code_analysis.dag.dag';
import * as fs from 'fs';
import { inferNode } from 'code_analysis.types.inferrer';
import { globalUri } from 'code_analysis.types.dag_bridge';
import { scopeAtOffset } from 'code_analysis.types.scope_walk';
import * as type_registry from 'code_analysis.types.registry';
import * as mode from 'code_analysis.mode';
import { localBinding } from 'code_analysis.bindings';

// Return an LSP Location object for byte offset inside uri.
function location(uri, text, lineTable, byteOffset) {
	let pos = offsetToPosition(text, lineTable, byteOffset);
	return { uri, range: { start: pos, end: pos } };
}

// Extract the identifier matching name from a function_declaration or
// lexical_declaration node. Returns the identifier node or null.
function findExportName(decl, name, text) {
	let dt = ts.nodeType(decl);
	if (dt === 'function_declaration') {
		let nameNode = ts.childByField(decl, 'name');
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
	for (let stmt in mode.topLevelStatements(root)) {
		let nt = ts.nodeType(stmt);

		if (nt === 'lexical_declaration') {
			for (let j = 0; j < ts.namedChildCount(stmt); j++) {
				let vd = ts.namedChild(stmt, j);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nameNode = ts.childByField(vd, 'name');
				if (nameNode && ts.text(nameNode, doc.text) === name)
					return location(uri, doc.text, doc.lineTable, ts.startByte(nameNode));
			}
		} else if (nt === 'function_declaration') {
			let nameNode = ts.childByField(stmt, 'name');
			if (nameNode && ts.text(nameNode, doc.text) === name)
				return location(uri, doc.text, doc.lineTable, ts.startByte(nameNode));
		} else if (nt === 'export_statement') {
			let decl = ts.childByField(stmt, 'declaration');
			if (!decl) continue;
			let nameNode = findExportName(decl, name, doc.text);
			if (nameNode)
				return location(uri, doc.text, doc.lineTable, ts.startByte(nameNode));
		}
	}
	return null;
}

// Resolve `name` to its declaration in the enclosing lexical scope at `offset`.
function localScopeDef(root, uri, doc, name, offset) {
	let hit = localBinding(root, name, offset, doc.text);
	return hit ? location(uri, doc.text, doc.lineTable, ts.startByte(hit)) : null;
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
	let tree = mode.parse(text);
	let root = ts.rootNode(tree);
	let lineTable = buildLineTable(text);
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'export_statement') continue;
		let decl = ts.childByField(stmt, 'declaration');
		if (!decl) continue;
		let nameNode = findExportName(decl, name, text);
		if (nameNode)
			return location(resolvedUri, text, lineTable, ts.startByte(nameNode));
	}
	let doc = { uri: resolvedUri, text, tree, lineTable };
	return localDefinition(resolvedUri, doc, name);
}

// If cursor is on a property_identifier inside a member_expression, resolve
// via namespace import DAG or scope-based type inference.
// Handles both simple `obj.prop` (objNode is identifier) and chained `a.b.prop`
// (objNode is a member_expression — inferNode recurses through the chain).
function memberExprDef(uri, doc, memberExpr, propName, offset) {
	let objNode = ts.childByField(memberExpr, 'object');
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

// A Location pointing at the top of the file that `spec` resolves to, or null.
// Used for jumps to a whole module (namespace-style: require / module variable).
function moduleFileLocation(spec) {
	let modUri = dag.resolveSpecifier(spec);
	if (!modUri) return null;
	return { uri: modUri, range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } } };
}

// If strNode is the string specifier of a `require("...")` call, return the
// Location of the module it names. `require` is ucode's runtime module loader,
// so its literal argument behaves like an import specifier for navigation. A
// locally-declared `require` is not the builtin loader, so it is not treated as
// such (mirrors requireModuleType's shadow guard in the inferrer).
function requireStringTarget(uri, doc, strNode, offset) {
	let argsNode = ts.parent(strNode);
	if (!argsNode || ts.nodeType(argsNode) !== 'arguments') return null;
	let call = ts.parent(argsNode);
	if (!call || ts.nodeType(call) !== 'call_expression') return null;
	let fnNode = ts.childByField(call, 'function');
	if (!fnNode || ts.nodeType(fnNode) !== 'identifier' ||
	    ts.text(fnNode, doc.text) !== 'require') return null;
	if (localScopeDef(ts.rootNode(doc.tree), uri, doc, 'require', offset)) return null;
	let spec = stringLiteralText(strNode, doc.text);
	return length(spec) ? moduleFileLocation(spec) : null;
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

	// The string specifier of require("...") → jump to the module file.
	if (nt === 'string' || nt === 'string_fragment') {
		let strNode = (nt === 'string_fragment') ? ts.parent(node) : node;
		return strNode ? requireStringTarget(uri, doc, strNode, offset) : null;
	}

	if (nt !== 'identifier') return null;

	let name = ts.text(node, doc.text);

	// Named import → jump to the exporting file.
	let imp = importedDefinition(uri, name);
	if (imp) return imp;

	// Namespace import alias → jump to the module file.
	let ns = namespaceDef(uri, name);
	if (ns) return ns;

	// A variable bound to a module value (e.g. `let fw4 = require("fw4")`) →
	// jump to the module file, mirroring a namespace import alias. At the
	// declaration site itself the name is not yet in scope, so this applies to
	// use sites; the string case above covers the declaration.
	let scope = scopeAtOffset(doc.scopeMap, offset);
	let vt = inferNode(node, doc.text, uri, scope, 0);
	if (vt && vt.kind === 'module') {
		let modLoc = moduleFileLocation(vt.path);
		if (modLoc) return modLoc;
	}

	// Local binding in the innermost enclosing scope: parameters, block-local
	// let/const, nested function declarations, loop and catch variables.
	let scoped = localScopeDef(root, uri, doc, name, offset);
	if (scoped) return scoped;

	// Top-level declaration.
	let local = localDefinition(uri, doc, name);
	if (local) return local;

	// Builtin: jump to its declaration in global.d.uc.
	let gUri = globalUri();
	return gUri ? resolveExportDefinition(gUri, name) : null;
};
