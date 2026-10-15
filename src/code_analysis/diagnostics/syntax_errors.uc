import * as ts from 'tree_sitter';
import { rangeOf } from 'code_analysis.positions';

let SEVERITY_ERROR = 1;

// Walk the AST and collect all ERROR and MISSING nodes.
// tree-sitter inserts an ERROR node wherever it could not parse the source
// (the node's text is the fragment that caused the error), and a zero-width
// MISSING node where inserting one token was enough to recover — e.g. the
// `}` of a block left open at the end of the file. MISSING tokens are often
// anonymous, so all children are walked, but only those that hold an error.
function collectErrors(node, text, lineTable, out) {
	let message;
	if (ts.nodeType(node) === 'ERROR')
		message = 'Syntax error';
	else if (ts.isMissing(node))
		message = sprintf("Syntax error: missing '%s'", ts.nodeType(node));

	if (message) {
		push(out, {
			range:    rangeOf(text, lineTable, node),
			severity: SEVERITY_ERROR,
			source:   'ucode-ls',
			code:     'syntax-error',
			message,
		});
		return;
	}
	for (let i = 0; i < ts.childCount(node); i++) {
		let c = ts.child(node, i);
		if (ts.hasError(c))
			collectErrors(c, text, lineTable, out);
	}
}

export function syntaxErrors(doc) {
	let lineTable = doc.lineTable;
	let diags = [];
	collectErrors(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	return diags;
};
