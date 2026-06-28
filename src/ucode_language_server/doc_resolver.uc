import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag.dag';
import { inferNode, stdlibUri } from 'ucode_language_server.types.inferrer';

function namedImportDoc(uri, name) {
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

function ownExportDoc(uri, name) {
	let exp = dag.resolveExport(uri, name);
	return (exp && exp.doc) ? exp.doc : null;
}

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

function memberDoc(uri, propNode, source, scope) {
	let parent = ts.parent(propNode);
	if (!parent || ts.nodeType(parent) !== 'member_expression') return null;
	let objNode  = ts.namedChild(parent, 0);
	let propName = ts.text(propNode, source);
	let objType  = inferNode(objNode, source, uri, scope, 0);
	if (!objType) return null;
	if (objType.kind === 'module') {
		let r = dag.resolveMember(objType.path, propName);
		return (r && r.exp.doc) ? r.exp.doc : null;
	}
	if (objType.kind === 'record') {
		for (let i = 0; i < length(objType.fields); i++) {
			let f = objType.fields[i];
			if (f.name === propName && f.doc) return f.doc;
		}
	}
	return null;
}

// Resolve JSDoc for the node under the cursor. Tries, in order:
//   identifier          -> named import -> own-file export -> stdlib builtin
//   property_identifier -> module member -> record field
// Returns null when no documentation is found.
export function resolveDoc(uri, node, source, scope) {
	let ntype = ts.nodeType(node);
	if (ntype === 'identifier') {
		let name = ts.text(node, source);
		return namedImportDoc(uri, name) ?? ownExportDoc(uri, name) ?? builtinDoc(name);
	}
	if (ntype === 'property_identifier')
		return memberDoc(uri, node, source, scope);
	return null;
};
