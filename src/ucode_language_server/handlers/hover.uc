import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { inferNode, buildScope, stdlibUri } from 'ucode_language_server.types.inferrer';
import { typeToString } from 'ucode_language_server.types.doc_parser';
import * as dag from 'ucode_language_server.dag.dag';
import * as templates from 'ucode_language_server.templates';

function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
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

function resolvedExportDoc(uri, name) {
	let exp = dag.resolveExport(uri, name);
	return (exp && exp.doc) ? exp.doc : null;
}

function modulePropertyDoc(uri, propNode, source, scope) {
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

// Build the structured context object passed to hover templates.
// Merges inferred type fields with JSDoc descriptions so templates
// receive pre-resolved, ready-to-render data.
function buildHoverCtx(label, type, doc) {
	let ctx = {
		label,
		kind:    type.kind,
		typeStr: typeToString(type),
		doc:     doc ? { description: doc.description ?? null, examples: doc.examples ?? [] } : null,
		typeToString,
	};

	if (type.kind === 'function') {
		// Build a merged params list: inferred typeStr + JSDoc description.
		// type.params is derived from doc.params so names align reliably.
		let docParamMap = {};
		for (let p in (doc?.params ?? []))
			docParamMap[p.name] = p;
		ctx.params = map(type.params ?? [], (p) => {
			let dp = docParamMap[p.name];
			return {
				name: p.name,
				typeStr: typeToString(p.type),
				description: dp?.description ?? null,
			};
		});
		ctx.returns = type.returns ? {
			typeStr: typeToString(type.returns),
			description: doc?.returns?.description ?? null,
		} : null;
	}

	if (type.kind === 'record') {
		ctx.fields = map(type.fields ?? [], (f) => ({
			name: f.name,
			typeStr: f.type ? typeToString(f.type) : null,
			description: f.doc?.description ?? null,
		}));
	}

	if (type.kind === 'module') {
		let modUri = dag.resolveSpecifier(type.path);
		let modDoc = null;
		if (modUri) {
			if (!dag.exportsOf(modUri)) dag.addFromDisk(modUri);
			modDoc = dag.moduleDocOf(modUri);
		}
		ctx.module = {
			specifier: type.path,
			description: modDoc?.description ?? null,
		};
	}

	return ctx;
}

export function hover(doc, position, config) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	let scope = buildScope(doc.uri, doc.text, doc.tree, ts.startByte(node));
	let type = inferNode(node, doc.text, doc.uri, scope, 0);

	if (type.kind === 'unknown') return null;

	let label = ts.text(node, doc.text);

	let expDoc = null;
	if (ts.nodeType(node) === 'identifier') {
		expDoc = importedDoc(doc.uri, label) ?? resolvedExportDoc(doc.uri, label);
		if (!expDoc && type.kind !== 'module') expDoc = builtinDoc(label);
	} else if (ts.nodeType(node) === 'property_identifier') {
		expDoc = modulePropertyDoc(doc.uri, node, doc.text, scope);
	}

	let ctx = buildHoverCtx(label, type, expDoc);

	let templateName = 'hover/' + (
		type.kind === 'function' ? 'function' :
		type.kind === 'record'   ? 'record'   :
		type.kind === 'module'   ? 'module'   :
		                           'default'
	);

	let md = templates.renderTemplate(templateName, ctx, config ?? {});

	if (md === null) {
		// Fallback when no template file is found (misconfigured selfSrcDir).
		md = sprintf('```ucode\n%s: %s\n```', label, ctx.typeStr);
		if (expDoc?.description) md += '\n\n' + expDoc.description;
	}

	return { contents: { kind: 'markdown', value: md } };
};
