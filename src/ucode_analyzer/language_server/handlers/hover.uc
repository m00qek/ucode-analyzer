import * as ts from 'tree_sitter';
import { positionToOffset, nodeAtOffset, docBefore } from 'ucode_analyzer.code_analysis.positions';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { typeToString, parseDoc } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { UNKNOWN, STR, resolveRef } from 'ucode_analyzer.code_analysis.types.type_utils';
import { returnOf } from 'ucode_analyzer.code_analysis.types.unifier';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as templates from 'ucode_analyzer.language_server.templates';
import { resolveDoc } from 'ucode_analyzer.code_analysis.doc_resolver';
import { exportType } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import * as platform from 'ucode_analyzer.language_server.platform';

// Build the structured context object passed to hover templates.
// Merges inferred type fields with JSDoc descriptions so templates
// receive pre-resolved, ready-to-render data.
function buildHoverCtx(label, type, doc) {
	// A typedef name keeps its name in typeStr but renders as what it names.
	let shape = resolveRef(type);
	if (shape?.kind === 'nullable') shape = shape.inner;
	let ctx = {
		label,
		kind:    shape.kind,
		typeStr: typeToString(type),
		doc:     doc ? { description: doc.description ?? null, examples: doc.examples ?? [], see: doc.see ?? [] } : null,
		typeToString,
	};

	if (shape.kind === 'function') {
		let docParams = doc?.params ?? [];
		let docParamMap = {};
		for (let p in docParams)
			docParamMap[p.name] = p;
		let all = map(shape.params ?? [], (p) => ({
			name: p.name,
			rest: !!p.rest,
			typeStr: typeToString(p.type),
			description: docParamMap[p.name]?.description ?? null,
		}));
		// Only show the Parameters section when at least one @param is documented.
		ctx.params = length(docParams) > 0 ? all : [];
		let ret = returnOf(shape);
		ctx.returns = ret ? {
			typeStr: typeToString(ret),
			description: doc?.returns?.description ?? null,
		} : null;
		// Pre-built declaration-form signature for the code fence.
		ctx.signature = sprintf('function %s(%s): %s',
			label,
			join(', ', map(all, (p) => (p.rest ? '...' : '') +
				(!p.name ? p.typeStr : p.typeStr === '?' ? p.name : p.name + ': ' + p.typeStr))),
			ctx.returns ? ctx.returns.typeStr : '?'
		);
	}

	if (shape.kind === 'record') {
		ctx.fields = map(shape.fields ?? [], (f) => ({
			name: f.name,
			typeStr: f.type ? typeToString(f.type) : null,
			description: f.doc?.description ?? null,
		}));
	}

	if (shape.kind === 'module') {
		let modUri = dag.resolveSpecifier(shape.path);
		let modDoc = null;
		if (modUri) {
			if (!dag.exportsOf(modUri)) dag.addFromDisk(modUri);
			modDoc = dag.moduleDocOf(modUri);
		}
		ctx.module = {
			specifier: shape.path,
			description: modDoc?.description ?? null,
			members: map(modUri ? (dag.exportsOf(modUri) ?? []) : [], (e) => {
				let t = exportType(e, modUri);
				return { name: e.name, typeStr: t.kind === 'unknown' ? null : typeToString(t) };
			}),
		};
	}

	return ctx;
}

function renderCtx(ctx, templateName, config) {
	let md = templates.renderTemplate(templateName, ctx, config ?? {});
	if (md === null)
		md = sprintf('```ucode\n%s: %s\n```', ctx.label, ctx.typeStr);
	return { contents: { kind: 'markdown', value: md } };
}

// ── Case 1: function parameter at its declaration site ─────────────────────
//
// inferNode returns UNKNOWN for a param identifier because the param isn't in
// scope at its own declaration position.  Instead, read the @param entry from
// the function's JSDoc comment.
function hoverParam(node, formalParams, doc, config) {
	let paramName = ts.text(node, doc.text);
	let funcNode  = ts.parent(formalParams);
	if (!funcNode) return null;

	let checkNode   = funcNode;
	let checkParent = ts.parent(funcNode) ?? ts.rootNode(doc.tree);
	if (ts.nodeType(checkParent) === 'export_statement') {
		checkNode   = checkParent;
		checkParent = ts.parent(checkNode) ?? ts.rootNode(doc.tree);
	}

	let docText = docBefore(checkNode, checkParent, doc.text);
	if (!docText) return null;

	let funcDoc = parseDoc(docText);
	for (let p in (funcDoc?.params ?? [])) {
		if (p.name !== paramName) continue;
		let paramType = p.type ?? { kind: 'unknown' };
		let ctx = buildHoverCtx(paramName, paramType, { description: p.description, examples: [], see: [] });
		return renderCtx(ctx, 'hover/default', config);
	}

	return null;
}

// ── Case 2: for-in loop variable at its declaration site ───────────────────
//
// The loop variable (the `variable` or `key` field of for_in_statement) only
// enters scope inside the body block, so looking it up in the scope at
// startByte(forIn) won't find it.  Infer the iterable's element type directly
// from the `object` field.
function hoverForInVar(node, forIn, doc, config) {
	let left = ts.childByField(forIn, 'variable') ?? ts.childByField(forIn, 'key');
	if (!left || ts.startByte(left) !== ts.startByte(node)) return null;

	let scope    = scopeAtOffset(doc.scopeMap, ts.startByte(forIn));
	let right    = ts.childByField(forIn, 'object');
	let elemType = UNKNOWN;
	if (right) {
		let iterType = inferNode(right, doc.text, doc.uri, scope, 0);
		if (iterType.kind === 'nullable') iterType = iterType.inner;
		if (iterType.kind === 'generic' && iterType.base === 'list' && length(iterType.params) > 0)
			elemType = iterType.params[0];
		else if (iterType.kind === 'record' || (iterType.kind === 'generic' && iterType.base === 'dict'))
			elemType = STR;
	}
	if (elemType.kind === 'unknown') return null;

	let ctx = buildHoverCtx(ts.text(node, doc.text), elemType, null);
	return renderCtx(ctx, 'hover/default', config);
}

// ── Case 3: general path ───────────────────────────────────────────────────
//
// Build scope at the cursor, infer the node's type, resolve JSDoc from the
// declaration site (import, own-file export, or stdlib builtin), then render
// via the template matching the type kind.
function hoverGeneral(node, doc, config) {
	let scope = scopeAtOffset(doc.scopeMap, ts.startByte(node));
	let type  = inferNode(node, doc.text, doc.uri, scope, 0);
	// If scope lookup returned UNKNOWN and this is a declaration name, infer
	// the type from the initializer instead (scope_walk emits before the stmt,
	// so the name isn't visible at its own declaration offset).
	if (type.kind === 'unknown' && ts.nodeType(node) === 'identifier') {
		let parent = ts.parent(node);
		if (parent && ts.nodeType(parent) === 'variable_declarator') {
			let nameField = ts.childByField(parent, 'name');
			if (nameField && ts.startByte(nameField) === ts.startByte(node)) {
				let valNode = ts.childByField(parent, 'value');
				if (valNode) type = inferNode(valNode, doc.text, doc.uri, scope, 0);
			}
		}
	}
	if (type && type.kind === 'nullable') type = type.inner;
	if (type.kind === 'unknown' && ts.nodeType(node) !== 'identifier' && ts.nodeType(node) !== 'property_identifier')
		return null;

	let label    = ts.text(node, doc.text);
	let resolved = resolveDoc(doc.uri, node, doc.text, scope);
	let expDoc   = resolved.doc;
	let modUri   = resolved.modUri;
	// A name of unknown type still shows its documentation, if it has any.
	if (type.kind === 'unknown' && !expDoc?.description) return null;

	let ctx = buildHoverCtx(label, type, expDoc);
	ctx.since = expDoc?.since ?? null;
	if (modUri && ctx.since)
		ctx.unavailable = !platform.symbolAvailable(modUri, ctx.since);

	let templateName = 'hover/' + (
		ctx.kind === 'function' ? 'function' :
		ctx.kind === 'record'   ? 'record'   :
		ctx.kind === 'module'   ? 'module'   :
		                           'default'
	);

	let md = templates.renderTemplate(templateName, ctx, config ?? {});
	if (md === null) {
		md = sprintf('```ucode\n%s: %s\n```', label, ctx.typeStr);
		if (expDoc?.description) md += '\n\n' + expDoc.description;
	}

	return { contents: { kind: 'markdown', value: md } };
}

// ── Dispatcher ─────────────────────────────────────────────────────────────
export function hover(doc, position, config) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);

	if (ts.nodeType(node) === 'identifier') {
		let parent     = ts.parent(node);
		let parentType = parent ? ts.nodeType(parent) : null;

		if (parentType === 'formal_parameters')
			return hoverParam(node, parent, doc, config);

		// Only the loop variable(s) need the dedicated element-type path; the
		// iterable (`object`) and anything else in the header get a normal hover.
		if (parentType === 'for_in_statement') {
			let left  = ts.childByField(parent, 'variable') ?? ts.childByField(parent, 'key');
			let value = ts.childByField(parent, 'value');
			let ns    = ts.startByte(node);
			if ((left && ts.startByte(left) === ns) || (value && ts.startByte(value) === ns))
				return hoverForInVar(node, parent, doc, config);
		}
	}

	return hoverGeneral(node, doc, config);
};
