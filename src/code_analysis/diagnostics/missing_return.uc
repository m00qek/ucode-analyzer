import * as ts from 'tree_sitter';
import { rangeOf, precedingDoc } from 'code_analysis.positions';
import { parseDoc } from 'code_analysis.types.doc_parser';
import { namedNonComments, firstNamed } from 'code_analysis.ast_text';

let SEVERITY_WARNING = 2;

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

// A statically truthy loop condition. Conservative: only bare `true` and a
// nonzero numeric literal count; anything else (identifiers, comparisons, calls)
// is treated as possibly-false so the loop is NOT assumed infinite.
function isConstTruthy(node, source) {
	if (!node) return false;
	let nt = ts.nodeType(node);
	if (nt === 'true') return true;
	if (nt === 'number') return (+ts.text(node, source)) != 0;
	return false;
}

// An infinite loop (`while(true)`/`while(1)` or `for(;;)`/`for(;true;)`) never
// exits normally, so control cannot fall past it. We do NOT analyse `break`, so a
// loop that can break is still treated as infinite — that only ever suppresses a
// warning (a possible false negative), never adds one (precision over recall).
function isInfiniteLoop(node, source) {
	let nt = ts.nodeType(node);
	if (nt === 'while_statement') {
		let cond = ts.childByField(node, 'condition');
		// while's condition is wrapped in a parenthesized_expression.
		return isConstTruthy(cond ? (firstNamed(cond) ?? cond) : null, source);
	}
	if (nt === 'for_statement') {
		// C-style for; an absent/empty condition clause means `for(;;)`.
		let cond = ts.childByField(node, 'condition');
		if (!cond || ts.nodeType(cond) === 'empty_statement') return true;
		return isConstTruthy(cond, source);
	}
	return false;
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
// A clause's last statement is its last non-comment child other than the case
// `value`.
function switchAlwaysReturns(node, source) {
	let body = ts.childByField(node, 'body');
	if (!body) return false;

	let clauses = [];
	let hasDefault = false;
	for (let c in ts.namedChildren(body)) {
		let ct = ts.nodeType(c);
		if (ct !== 'switch_case' && ct !== 'switch_default') continue;
		if (ct === 'switch_default') hasDefault = true;
		let value = ts.childByField(c, 'value');
		let stmts = filter(namedNonComments(c), (s) => !value || ts.startByte(s) !== ts.startByte(value));
		push(clauses, length(stmts) ? stmts[-1] : null);
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
//   if_statement: condition, consequence, alternative (else_clause, optional)
//     else_clause: its one statement (a block or an if_statement)
//   if_alt_statement (`if (c): … elif (c): … else … endif`)
//     consequence: statement_list, elif_clause*: { consequence: statement_list },
//     alternative: else_alt_clause { statement_list } — every list is absent
//     when its body is empty
alwaysReturns = function(node, source) {
	if (!node) return false;
	let nt = ts.nodeType(node);
	if (nt === 'return_statement') return true;
	if (nt === 'expression_statement')
		return isNoReturnCall(firstNamed(node), source);
	if (nt === 'else_clause') return alwaysReturns(firstNamed(node), source);
	if (nt === 'statement_block' || nt === 'statement_list') {
		let stmts = namedNonComments(node);
		return length(stmts) > 0 && alwaysReturns(stmts[-1], source);
	}
	if (nt === 'if_alt_statement') {
		let alt = ts.childByField(node, 'alternative');
		if (!alt || !alwaysReturns(ts.childByField(node, 'consequence'), source)) return false;
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let c = ts.namedChild(node, i);
			if (ts.nodeType(c) === 'elif_clause' &&
			    !alwaysReturns(ts.childByField(c, 'consequence'), source)) return false;
		}
		return alwaysReturns(firstNamed(alt), source);
	}
	if (nt === 'if_statement') {
		let alt = ts.childByField(node, 'alternative');
		return !!alt && alwaysReturns(ts.childByField(node, 'consequence'), source) &&
		       alwaysReturns(alt, source);
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
	// An infinite loop never falls through, so a function body ending in one
	// needs no return on the fall-through path.
	if (nt === 'while_statement' || nt === 'for_statement')
		return isInfiniteLoop(node, source);
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
	let target = ts.childByField(node, 'name') ?? node;

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
