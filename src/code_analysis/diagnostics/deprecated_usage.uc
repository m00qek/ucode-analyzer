import * as ts from 'tree_sitter';
import * as dag from 'code_analysis.dag.dag';
import { buildLineTable, rangeOf } from 'code_analysis.positions';
import { resolveDoc } from 'code_analysis.doc_resolver';
import { globalUri } from 'code_analysis.types.dag_bridge';

let SEVERITY_HINT  = 4;
let TAG_DEPRECATED = 2;

// Returns true when the identifier node is the binding name at its declaration
// site, not a reference.  These must not emit deprecated warnings.
function isDeclSite(node) {
	let parent = ts.parent(node);
	if (!parent) return false;
	let pt = ts.nodeType(parent);
	if (pt === 'variable_declarator' || pt === 'function_declaration') {
		let first = ts.namedChild(parent, 0);
		return first && ts.startByte(first) === ts.startByte(node);
	}
	if (pt === 'import_specifier' || pt === 'export_specifier' ||
	    pt === 'formal_parameters' || pt === 'namespace_import')
		return true;
	return false;
}

// True if `modUri` exports `name` (directly or via a re-export chain) with a
// deprecated JSDoc. Mirrors the resolution order resolveDoc uses.
function exportIsDeprecated(modUri, name) {
	let exps = dag.exportsOf(modUri);
	if (exps)
		for (let i = 0; i < length(exps); i++)
			if (exps[i].name === name && exps[i].doc && exps[i].doc.deprecated)
				return true;
	let exp = dag.resolveExport(modUri, name);
	return !!(exp && exp.doc && exp.doc.deprecated);
}

// The set of identifier names that could possibly resolve to a deprecated
// symbol in this file: deprecated own exports, imported names bound to a
// deprecated export, and deprecated builtins. Computed once so the per-node walk
// only pays the expensive resolveDoc for names that can actually be deprecated
// (the vast majority never are). resolveDoc still does the authoritative check,
// so this gate changes cost, not results.
function deprecatedNames(uri) {
	let names = {};

	let own = dag.exportsOf(uri);
	if (own)
		for (let i = 0; i < length(own); i++)
			if (own[i].doc && own[i].doc.deprecated) names[own[i].name] = true;

	let imps = dag.importsOf(uri);
	if (imps)
		for (let i = 0; i < length(imps); i++) {
			let imp = imps[i];
			if (!imp.resolvedUri) continue;
			for (let s = 0; s < length(imp.symbols ?? []); s++) {
				let local  = imp.symbols[s];
				let remote = (imp.renames && imp.renames[local]) ?? local;
				if (exportIsDeprecated(imp.resolvedUri, remote)) names[local] = true;
			}
		}

	let bUri = globalUri();
	if (bUri) {
		let bexps = dag.exportsOf(bUri);
		if (bexps)
			for (let i = 0; i < length(bexps); i++)
				if (bexps[i].doc && bexps[i].doc.deprecated) names[bexps[i].name] = true;
	}

	return names;
}

function walk(node, source, uri, lineTable, candidates, diags) {
	if (ts.nodeType(node) === 'identifier' &&
	    candidates[ts.text(node, source)] && !isDeclSite(node)) {
		let resolved = resolveDoc(uri, node, source, null);
		if (resolved.doc && resolved.doc.deprecated)
			push(diags, {
				range:    rangeOf(source, lineTable, node),
				severity: SEVERITY_HINT,
				source:   'ucode-ls',
				code:     'deprecated',
				tags:     [ TAG_DEPRECATED ],
				message:  'Deprecated',
			});
	}
	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, uri, lineTable, candidates, diags);
}

export function deprecatedUsage(uri, doc) {
	let candidates = deprecatedNames(uri);
	// Nothing in scope is deprecated → no identifier can be, skip the walk.
	if (length(candidates) === 0) return [];

	let lineTable = buildLineTable(doc.text);
	let diags     = [];
	walk(ts.rootNode(doc.tree), doc.text, uri, lineTable, candidates, diags);
	return diags;
};
