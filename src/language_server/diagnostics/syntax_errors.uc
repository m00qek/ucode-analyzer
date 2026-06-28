import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';

let SEVERITY_ERROR = 1;

// Walk the AST and collect all ERROR nodes.
// tree-sitter inserts an ERROR node wherever it could not parse the source;
// the node's text is the fragment that caused the error.
function collectErrors(node, text, lineTable, out) {
	if (ts.nodeType(node) === 'ERROR') {
		push(out, {
			range:    rangeOf(text, lineTable, node),
			severity: SEVERITY_ERROR,
			message:  'Syntax error',
		});
		return;
	}
	for (let i = 0; i < ts.namedChildCount(node); i++)
		collectErrors(ts.namedChild(node, i), text, lineTable, out);
}

export function syntaxErrors(doc) {
	let lineTable = buildLineTable(doc.text);
	let diags = [];
	collectErrors(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	return diags;
};
