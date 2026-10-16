// Bridges the cross-file dependency graph into the type system: it converts DAG
// export records into Types, resolves imported names/members to their exported
// types, and builds the per-file import scope and the builtin scope. None of it
// participates in the `inferrer._infer` recursion — the dependency is one-way
// (inferrer imports from here, never the reverse), which is why it lives apart.

import * as dag from 'code_analysis.dag.dag';
import { UNKNOWN } from 'code_analysis.types.type_utils';
import { makeScope, scopeSet } from 'code_analysis.types.scope';

let _builtinScope = makeScope(null);
let _globalUri    = null;

// ── DAG export → Type ──────────────────────────────────────────────────────

export function exportType(exp, sourceUri) {
	if (exp._moduleSpecifier) return { kind: 'module', path: exp._moduleSpecifier };
	if (exp.doc?.type) return exp.doc.type;
	if (exp.kind === 'function' || (exp.doc && (length(exp.doc.params) > 0 || exp.doc.returns))) {
		if (!exp.doc) return { kind: 'function', params: [], return: UNKNOWN };
		return {
			kind: 'function',
			params: map(filter(exp.doc.params, (p) => !match(p.name, /\./)), (p) => ({ name: p.name, type: p.type ?? UNKNOWN })),
			return: (exp.doc.returns ? exp.doc.returns.type : null) ?? UNKNOWN,
		};
	}
	if (exp.properties) {
		let fields = [];
		for (let i = 0; i < length(exp.properties); i++) {
			let prop = exp.properties[i];
			push(fields, { name: prop.name, type: exportType(prop, sourceUri), doc: prop.doc, position: prop.position });
		}
		return { kind: 'record', fields, sourceUri };
	}
	if (!exp.doc) return UNKNOWN;
	return (exp.doc.returns ? exp.doc.returns.type : null) ?? UNKNOWN;
};

// ── Imported-name resolution ───────────────────────────────────────────────

// Look up a symbol imported by name into uri (import { foo } from 'mod').
export function dagNamedLookup(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let loc = dag.resolveExportLocation(imp.resolvedUri, remoteName);
		let exp = dag.resolveExport(loc.uri, loc.name);
		if (exp) return exportType(exp, loc.uri);
	}
	return null;
};

// Look up a member of a namespace-imported alias (import * as mod from 'x').
export function dagMemberLookup(uri, alias, member) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias !== alias || !imp.resolvedUri) continue;
		let loc = dag.resolveExportLocation(imp.resolvedUri, member);
		let exp = dag.resolveExport(loc.uri, loc.name);
		return exp ? exportType(exp, loc.uri) : null;
	}
	return null;
};

// ── Scope building ─────────────────────────────────────────────────────────

export function importScope(uri) {
	let scope = makeScope(_builtinScope);
	let imps = dag.importsOf(uri);
	if (!imps) return scope;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias) {
			// Namespace import: import * as alias from 'mod'
			if (imp.resolvedUri)
				scopeSet(scope, imp.alias, { kind: 'module', path: imp.specifier });
			continue;
		}
		if (!imp.resolvedUri) continue;
		for (let j = 0; j < length(imp.symbols); j++) {
			let localName = imp.symbols[j];
			let remoteName = (imp.renames && imp.renames[localName]) ?? localName;
			let loc = dag.resolveExportLocation(imp.resolvedUri, remoteName);
			let r = dag.resolveExport(loc.uri, loc.name);
			if (r) scopeSet(scope, localName, exportType(r, loc.uri));
		}
	}
	return scope;
};

export function globalUri() { return _globalUri; };

export function initBuiltinsFromDag(uri) {
	let exps = dag.exportsOf(uri);
	if (!exps || length(exps) === 0) return;
	_globalUri = uri;
	let s = makeScope(null);
	for (let i = 0; i < length(exps); i++)
		scopeSet(s, exps[i].name, exportType(exps[i], uri));
	_builtinScope = s;
};
