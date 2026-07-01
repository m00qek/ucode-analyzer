import * as ts from 'tree_sitter';
import { rangeOf, docBefore } from 'code_analysis.positions';
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

// A bare call to die()/exit() never returns, so a path ending in one is as
// terminating as a `return`. Mirrors isNoReturnCall in types/scope_walk.uc.
function isNoReturnCall(node, source) {
	if (!node || ts.nodeType(node) !== 'call_expression') return false;
	let callee = ts.childByField(node, 'function');
	if (!callee || ts.nodeType(callee) !== 'identifier') return false;
	let name = ts.text(callee, source);
	return name === 'die' || name === 'exit';
}

// Forward declaration: switchAlwaysReturns and alwaysReturns are mutually
// recursive and ucode does not hoist function declarations, so the name must
// exist before switchAlwaysReturns closes over it.
let alwaysReturns;

// A `switch` guarantees a return only if it has a `default` (otherwise an
// unmatched value falls out) and every clause, once entered, returns. ucode
// switches fall through C-style, so a clause with no terminating return inherits
// the next clause's fate; a `break` exits the switch (does not return). Scanning
// clauses back-to-front resolves the fall-through: nextReturns seeds false (past
// the last clause control leaves the switch).
//   switch_body
//     switch_case      namedChild(0)=value, rest=body statements
//     switch_default   all namedChildren are body statements
function switchAlwaysReturns(node, source) {
	let body = null;
	for (let i = 0; i < ts.namedChildCount(node); i++)
		if (ts.nodeType(ts.namedChild(node, i)) === 'switch_body') { body = ts.namedChild(node, i); break; }
	if (!body) return false;

	let clauses = [];
	let hasDefault = false;
	for (let i = 0; i < ts.namedChildCount(body); i++) {
		let c  = ts.namedChild(body, i);
		let ct = ts.nodeType(c);
		if (ct !== 'switch_case' && ct !== 'switch_default') continue;
		if (ct === 'switch_default') hasDefault = true;
		let first = (ct === 'switch_case') ? 1 : 0;   // skip the case value expression
		let last  = ts.namedChildCount(c) - 1;
		push(clauses, last >= first ? ts.namedChild(c, last) : null);
	}
	if (!hasDefault) return false;

	let nextReturns = false;
	for (let i = length(clauses) - 1; i >= 0; i--) {
		let lastStmt = clauses[i];
		let returns;
		if (!lastStmt)                                    returns = nextReturns;   // empty clause falls through
		else if (alwaysReturns(lastStmt, source))         returns = true;
		else if (ts.nodeType(lastStmt) === 'break_statement') returns = false;     // break exits the switch
		else                                              returns = nextReturns;   // falls through to next clause
		if (!returns) return false;
		nextReturns = returns;
	}
	return true;
}

// AST shape (tree-sitter-ucode):
//   if_statement
//     namedChild(0): parenthesized_expression  ← condition
//     namedChild(1): statement_block            ← consequent
//     namedChild(2): else_clause                ← optional
//       namedChild(0): statement_block | if_statement
alwaysReturns = function(node, source) {
	if (!node) return false;
	let nt = ts.nodeType(node);
	if (nt === 'return_statement') return true;
	if (nt === 'expression_statement')
		return isNoReturnCall(ts.namedChild(node, 0), source);
	if (nt === 'else_clause') return alwaysReturns(ts.namedChild(node, 0), source);
	if (nt === 'statement_block') {
		let n = ts.namedChildCount(node);
		return n > 0 && alwaysReturns(ts.namedChild(node, n - 1), source);
	}
	if (nt === 'if_statement') {
		if (ts.namedChildCount(node) < 3) return false;
		let cons = ts.namedChild(node, 1);
		let alt  = ts.namedChild(node, 2);
		return alwaysReturns(cons, source) && alwaysReturns(alt, source);
	}
	// try/catch returns only if the normal path AND the catch path both return.
	// (ucode has no `finally`; a try must have a catch.)
	if (nt === 'try_statement') {
		let body    = ts.childByField(node, 'body');
		let handler = ts.childByField(node, 'handler');
		if (!body || !handler) return false;
		let catchBody = ts.childByField(handler, 'body');
		return alwaysReturns(body, source) && alwaysReturns(catchBody, source);
	}
	if (nt === 'switch_statement')
		return switchAlwaysReturns(node, source);
	return false;
};

function checkFunction(node, source, lineTable, diags) {
	let docTxt = precedingDoc(node, source);
	if (!docTxt) return;
	let doc = parseDoc(docTxt);
	if (!hasConcreteReturn(doc)) return;

	let body = ts.childByField(node, 'body');
	if (!body || alwaysReturns(body, source)) return;

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
	let lineTable = doc.lineTable;
	let diags     = [];
	walk(root, source, lineTable, diags);
	return diags;
};
