import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { inferNode, buildScope } from 'ucode_language_server.types.inferrer';
import { typeToString } from 'ucode_language_server.types.doc_parser';
import * as dag from 'ucode_language_server.dag.dag';
import * as templates from 'ucode_language_server.templates';
import { resolveDoc } from 'ucode_language_server.doc_resolver';

function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
}

// JSDoc descriptions often start with "- text" (dash from @param formatting).
// Strip the leading dash so it doesn't combine with the template's "—" separator.
function cleanDesc(s) {
	if (!s) return null;
	return replace(s, /^\s*[-–—]\s*/, '');
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
		let docParams = doc?.params ?? [];
		let docParamMap = {};
		for (let p in docParams)
			docParamMap[p.name] = p;
		// Only show the Parameters section when at least one @param is documented.
		ctx.params = length(docParams) > 0
			? map(type.params ?? [], (p) => {
				let dp = docParamMap[p.name];
				return {
					name: p.name,
					typeStr: typeToString(p.type),
					description: cleanDesc(dp?.description),
				};
			})
			: [];
		ctx.returns = type.returns ? {
			typeStr: typeToString(type.returns),
			description: cleanDesc(doc?.returns?.description),
		} : null;
		// Pre-built declaration-form signature for the code fence.
		ctx.signature = sprintf('function %s(%s): %s',
			label,
			join(', ', map(ctx.params, (p) => p.name + ': ' + p.typeStr)),
			ctx.returns ? ctx.returns.typeStr : '?'
		);
	}

	if (type.kind === 'record') {
		ctx.fields = map(type.fields ?? [], (f) => ({
			name: f.name,
			typeStr: f.type ? typeToString(f.type) : null,
			description: cleanDesc(f.doc?.description),
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

	let expDoc = resolveDoc(doc.uri, node, doc.text, scope);

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
