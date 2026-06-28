import * as ts from 'tree_sitter';
import { inferNode, processDecl, importScope } from 'ucode_language_server.types.inferrer';
import { makeScope, scopeGet, scopeSet } from 'ucode_language_server.types.scope';
import { UNKNOWN, STR } from 'ucode_language_server.types.type_utils';

// Return all function nodes (function_declaration / arrow_function /
// function_expression) that contain offset, outermost first.
function enclosingFunctions(root, offset) {
	let result = [];
	let stack = [root];
	while (length(stack) > 0) {
		let node = pop(stack);
		if (ts.startByte(node) > offset || offset >= ts.endByte(node)) continue;
		let nt = ts.nodeType(node);
		if (nt === 'function_declaration' || nt === 'arrow_function' || nt === 'function_expression')
			push(result, node);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			push(stack, ts.namedChild(node, i));
	}
	return result;
}

// Return all statement_block nodes containing offset, outermost first.
function enclosingBlocks(root, offset) {
	let result = [];
	let stack = [root];
	while (length(stack) > 0) {
		let node = pop(stack);
		if (ts.startByte(node) > offset || offset >= ts.endByte(node)) continue;
		if (ts.nodeType(node) === 'statement_block')
			push(result, node);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			push(stack, ts.namedChild(node, i));
	}
	return result;
}

// If block is the body of a for-in statement, add the loop variable to scope.
function addForInVar(block, source, uri, scope) {
	let forIn = ts.parent(block);
	if (!forIn || ts.nodeType(forIn) !== 'for_in_statement') return;
	let loopVar = ts.childByField(forIn, 'left');
	if (!loopVar || ts.nodeType(loopVar) !== 'identifier') return;
	let iterable = ts.childByField(forIn, 'right');
	let elemType = UNKNOWN;
	if (iterable) {
		let iterType = inferNode(iterable, source, uri, scope, 0);
		if (iterType.kind === 'nullable') iterType = iterType.inner;
		if (iterType.kind === 'generic' && iterType.base === 'list' && length(iterType.params) > 0)
			elemType = iterType.params[0];
		else if (iterType.kind === 'record' || (iterType.kind === 'generic' && iterType.base === 'dict'))
			elemType = STR;
	}
	scopeSet(scope, ts.text(loopVar, source), elemType);
}

// If block is the body of a catch_clause, add its parameter to scope.
function addCatchVar(block, source, uri, scope) {
	let clause = ts.parent(block);
	if (!clause || ts.nodeType(clause) !== 'catch_clause') return;
	let param = ts.childByField(clause, 'parameter');
	if (param && ts.nodeType(param) === 'identifier')
		scopeSet(scope, ts.text(param, source), UNKNOWN);
}

// If block is the body of a C-style for statement, add its initializer
// bindings (e.g. `let i = 0`) to scope.
function addForVar(block, source, uri, scope) {
	let forStmt = ts.parent(block);
	if (!forStmt || ts.nodeType(forStmt) !== 'for_statement') return;
	let init = ts.childByField(forStmt, 'initializer');
	if (init && ts.nodeType(init) === 'lexical_declaration')
		processDecl(init, source, uri, scope, 0);
}

// Process declarations visible at targetOffset within a flat list of statements.
// Nested blocks (for-in bodies, if-bodies, etc.) are handled by buildScope via
// enclosingBlocks — this function never recurses.
function processBlock(stmts, source, uri, scope, targetOffset) {
	for (let i = 0; i < length(stmts); i++) {
		let stmt = stmts[i];
		if (ts.startByte(stmt) >= targetOffset) break;
		let stype = ts.nodeType(stmt);

		if (stype === 'lexical_declaration') {
			processDecl(stmt, source, uri, scope, 0);

		} else if (stype === 'function_declaration') {
			let nameNode = ts.namedChild(stmt, 0);
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				scopeSet(scope, ts.text(nameNode, source), inferNode(stmt, source, uri, scope, 0));

		} else if (stype === 'export_statement') {
			let inner = ts.namedChild(stmt, 0);
			if (inner && ts.nodeType(inner) === 'lexical_declaration')
				processDecl(inner, source, uri, scope, 0);
			else if (inner && ts.nodeType(inner) === 'function_declaration') {
				let nameNode = ts.namedChild(inner, 0);
				if (nameNode && ts.nodeType(nameNode) === 'identifier')
					scopeSet(scope, ts.text(nameNode, source), inferNode(inner, source, uri, scope, 0));
			}

		} else if (stype === 'expression_statement') {
			let inner = ts.namedChild(stmt, 0);
			if (inner && ts.nodeType(inner) === 'assignment_expression') {
				let lhs = ts.childByField(inner, 'left');
				let rhs = ts.childByField(inner, 'right');
				if (lhs && rhs && ts.nodeType(lhs) === 'identifier') {
					let name = ts.text(lhs, source);
					let newType = inferNode(rhs, source, uri, scope, 0);
					if (scopeGet(scope, name) !== null && newType.kind !== 'unknown')
						scopeSet(scope, name, newType);
				}
			}
		}
	}
}

// Add the formal parameters of fn to scope by inferring its function type.
// For named functions this uses JSDoc @param annotations; for anonymous
// callbacks it derives param types from the call site via callbackExpectedType
// (invoked inside inferArrow).  Both paths go through inferNode so the result is
// cached and consistent with what inferCall sees.
function addParamScope(fn, source, uri, scope) {
	let fnType = inferNode(fn, source, uri, scope, 0);
	if (!fnType || fnType.kind !== 'function') return;
	for (let i = 0; i < length(fnType.params); i++) {
		let p = fnType.params[i];
		scopeSet(scope, p.name, p.type ?? UNKNOWN);
	}
}

// Build a scope chain for the given file at targetOffset.
//
// Each nesting level creates a child scope via makeScope(parent), so inner
// names shadow outer ones structurally rather than by overwrite order:
//   1. importScope   — named imports and namespace aliases (root of chain)
//   2. makeScope     — top-level lets/fns (shadows imports)
//   3. For each enclosing statement_block outermost-first, a new child scope:
//        a. If the block is the body of the next enclosing function, run
//           addParamScope first (params shadow block-level lets from outer scopes).
//        b. addForInVar / addForVar / addCatchVar — implicit loop/catch bindings
//        c. processBlock — declarations inside that block up to targetOffset
//   4. Any remaining enclosing functions (arrow fns with expression bodies, which
//      have no statement_block) each get their own child scope with addParamScope.
export function buildScope(uri, source, tree, targetOffset) {
	let scope = importScope(uri);
	let root = ts.rootNode(tree);

	scope = makeScope(scope);
	processBlock(ts.namedChildren(root), source, uri, scope, targetOffset);

	let fns    = enclosingFunctions(root, targetOffset);
	let blocks = enclosingBlocks(root, targetOffset);
	let fi = 0;

	for (let bi = 0; bi < length(blocks); bi++) {
		let block = blocks[bi];
		scope = makeScope(scope);
		// If this block is the body of the next enclosing function, add its
		// parameters before processing the block's own declarations.
		if (fi < length(fns)) {
			let fnBody = ts.childByField(fns[fi], 'body');
			if (fnBody && ts.startByte(fnBody) === ts.startByte(block)) {
				addParamScope(fns[fi], source, uri, scope);
				fi++;
			}
		}
		addForInVar(block, source, uri, scope);
		addForVar(block, source, uri, scope);
		addCatchVar(block, source, uri, scope);
		processBlock(ts.namedChildren(block), source, uri, scope, targetOffset);
	}

	// Arrow functions with expression bodies have no statement_block, so their
	// body never appears in enclosingBlocks — handle them here.
	for (; fi < length(fns); fi++) {
		scope = makeScope(scope);
		addParamScope(fns[fi], source, uri, scope);
	}

	return scope;
};
