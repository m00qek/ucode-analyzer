import * as ts from 'tree_sitter';
import { positionToOffset, nodeAtOffset, docBefore } from 'language_server.positions';
import { inferNode } from 'language_server.types.inferrer';
import { buildScope } from 'language_server.types.scope_builder';
import { typeToString, parseDoc } from 'language_server.types.doc_parser';
import * as dag from 'language_server.dag.dag';
import * as templates from 'language_server.templates';
import { resolveDoc } from 'language_server.doc_resolver';
import * as platform from 'language_server.platform';

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
		ctx.returns = type['return'] ? {
			typeStr: typeToString(type['return']),
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

	// Cursor on a parameter at its declaration site (not a reference inside the body).
	// inferNode returns UNKNOWN here because the param is not yet in scope,
	// so we handle it specially by looking up the @param in the function's JSDoc.
	if (ts.nodeType(node) === 'identifier') {
		let paramParent = ts.parent(node);
		if (paramParent && ts.nodeType(paramParent) === 'formal_parameters') {
			let paramName = ts.text(node, doc.text);
			let funcNode = ts.parent(paramParent);
			if (funcNode) {
				let checkNode = funcNode;
				let checkParent = ts.parent(funcNode) ?? root;
				if (ts.nodeType(checkParent) === 'export_statement') {
					checkNode = checkParent;
					checkParent = ts.parent(checkNode) ?? root;
				}
				let docText = docBefore(checkNode, checkParent, doc.text);
				if (docText) {
					let funcDoc = parseDoc(docText);
					for (let p in (funcDoc?.params ?? [])) {
						if (p.name !== paramName) continue;
						let paramType = p.type ?? { kind: 'unknown' };
						let ctx = buildHoverCtx(paramName, paramType, { description: cleanDesc(p.description), examples: [] });
						let md = templates.renderTemplate('hover/default', ctx, config ?? {});
						if (md === null)
							md = sprintf('```ucode\n%s: %s\n```', paramName, typeToString(paramType));
						return { contents: { kind: 'markdown', value: md } };
					}
				}
			}
			return null;
		}
	}

	let scope = buildScope(doc.uri, doc.text, doc.tree, ts.startByte(node));
	let type = inferNode(node, doc.text, doc.uri, scope, 0);

	if (type.kind === 'unknown') return null;

	let label = ts.text(node, doc.text);

	let resolved = resolveDoc(doc.uri, node, doc.text, scope);
	let expDoc = resolved.doc;
	let modUri = resolved.modUri;

	let ctx = buildHoverCtx(label, type, expDoc);
	ctx.since = expDoc?.since ?? null;
	if (modUri && ctx.since)
		ctx.unavailable = !platform.symbolAvailable(modUri, ctx.since);

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
