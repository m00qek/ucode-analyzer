import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf, docBefore } from 'code_analysis.positions';
import { parseDoc } from 'code_analysis.types.doc_parser';

let SEVERITY_WARNING = 2;

// Find the /** */ comment immediately preceding node inside its parent block.
// Mirrors the private precedingDoc() in inferrer.uc.
function precedingDoc(node, source) {
	let target = node;
	let p = ts.parent(target);
	while (p) {
		let pt = ts.nodeType(p);
		if (pt === 'program' || pt === 'statement_block') break;
		target = p;
		p = ts.parent(target);
	}
	return p ? docBefore(target, p, source) : null;
}

// Returns true when type is a documented non-void return type.
function hasConcreteReturn(doc) {
	if (!doc || !doc.returns || !doc.returns.type) return false;
	let t = doc.returns.type;
	if (t.kind === 'unknown') return false;
	if (t.kind === 'primitive' && t.name === 'void') return false;
	return true;
}

// AST shape (tree-sitter-ucode):
//   if_statement
//     namedChild(0): parenthesized_expression  ← condition
//     namedChild(1): statement_block            ← consequent
//     namedChild(2): else_clause                ← optional
//       namedChild(0): statement_block | if_statement
function alwaysReturns(node) {
	if (!node) return false;
	let nt = ts.nodeType(node);
	if (nt === 'return_statement') return true;
	if (nt === 'else_clause') return alwaysReturns(ts.namedChild(node, 0));
	if (nt === 'statement_block') {
		let n = ts.namedChildCount(node);
		return n > 0 && alwaysReturns(ts.namedChild(node, n - 1));
	}
	if (nt === 'if_statement') {
		if (ts.namedChildCount(node) < 3) return false;
		let cons = ts.namedChild(node, 1);
		let alt  = ts.namedChild(node, 2);
		return alwaysReturns(cons) && alwaysReturns(alt);
	}
	return false;
}

function checkFunction(node, source, lineTable, diags) {
	let docTxt = precedingDoc(node, source);
	if (!docTxt) return;
	let doc = parseDoc(docTxt);
	if (!hasConcreteReturn(doc)) return;

	let body = ts.childByField(node, 'body');
	if (!body || alwaysReturns(body)) return;

	// Point the diagnostic at the function name (function_declaration) or the
	// opening keyword token (function_expression / arrow_function).
	let target = ts.namedChild(node, 0);
	if (!target || ts.nodeType(target) !== 'identifier') target = node;

	push(diags, {
		range:    rangeOf(source, lineTable, target),
		severity: SEVERITY_WARNING,
		source:   'ucode-ls',
		code:     'missing-return',
		message:  "Not all code paths return a value",
	});
}

function walk(node, source, lineTable, diags) {
	let nt = ts.nodeType(node);
	if (nt === 'function_declaration' || nt === 'function_expression' || nt === 'arrow_function')
		checkFunction(node, source, lineTable, diags);

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, diags);
}

export function missingReturn(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = buildLineTable(source);
	let diags     = [];
	walk(root, source, lineTable, diags);
	return diags;
};
