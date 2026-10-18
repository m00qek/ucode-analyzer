import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { appendedClosers } from 'ucode_analyzer.code_analysis.mode';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

function syntaxError(node, text, lineTable, message) {
	return diagnostic(rangeOf(text, lineTable, node), Severity.ERROR, 'syntax-error', message);
}

// Walk the AST and collect all ERROR and MISSING nodes.
// tree-sitter inserts an ERROR node wherever it could not parse the source
// (the node's text is the fragment that caused the error), and a zero-width
// MISSING node where inserting one token was enough to recover — e.g. the
// `}` of a block left open at the end of the file. MISSING tokens are often
// anonymous, so all children are walked, but only those that hold an error.
function collectErrors(node, text, lineTable, out) {
	if (ts.nodeType(node) === 'ERROR')
		return push(out, syntaxError(node, text, lineTable, 'Syntax error'));
	if (ts.isMissing(node))
		return push(out, syntaxError(node, text, lineTable,
			sprintf("Syntax error: missing '%s'", ts.nodeType(node))));

	for (let i = 0; i < ts.childCount(node); i++) {
		let c = ts.child(node, i);
		if (ts.hasError(c))
			collectErrors(c, text, lineTable, out);
	}
}

// The last token of node.
function lastToken(node) {
	while (ts.childCount(node) > 0) node = ts.child(node, ts.childCount(node) - 1);
	return node;
}

// ucode's lexer reads a `/` right after `++` or `--` as the start of a regex,
// so `a++ / b`, which the grammar parses as a division, does not compile.
function slashAfterIncrement(root, text, lineTable, out) {
	if (index(text, '++') < 0 && index(text, '--') < 0) return;
	for (let bin in ts.descendants(root, ['binary_expression'])) {
		let op = ts.childByField(bin, 'operator');
		let left = ts.childByField(bin, 'left');
		if (!op || !left || ts.nodeType(op) !== '/') continue;
		let t = ts.nodeType(lastToken(left));
		if (t === '++' || t === '--')
			push(out, syntaxError(op, text, lineTable,
				sprintf("ucode reads '/' after '%s' as the start of a regex: write (%s) / …", t, ts.text(left, text))));
	}
}

export function syntaxErrors(doc) {
	let lineTable = doc.lineTable;
	let diags = [];
	collectErrors(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	slashAfterIncrement(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	// Closers mode.parse() appended to a small file whose open blocks made it
	// one ERROR: missing, like the MISSING nodes of a larger file. Past the end
	// of the text, their ranges clamp to it.
	for (let c in appendedClosers(doc.tree, doc.text))
		push(diags, syntaxError(c, doc.text, lineTable,
			sprintf("Syntax error: missing '%s'", ts.nodeType(c))));
	return diags;
};
