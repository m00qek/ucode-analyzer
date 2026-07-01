import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'code_analysis.positions';
import { resolveDoc } from 'code_analysis.doc_resolver';

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

function walk(node, source, uri, lineTable, diags) {
	if (ts.nodeType(node) === 'identifier' && !isDeclSite(node)) {
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
		walk(ts.namedChild(node, i), source, uri, lineTable, diags);
}

export function deprecatedUsage(uri, doc) {
	let lineTable = buildLineTable(doc.text);
	let diags     = [];
	walk(ts.rootNode(doc.tree), doc.text, uri, lineTable, diags);
	return diags;
};
