import * as ts from 'tree_sitter';
import { firstNamed, namedNonComments } from 'code_analysis.ast_text';
import { inferNode, declaredType } from 'code_analysis.types.inferrer';
import { importScope } from 'code_analysis.types.dag_bridge';
import { makeScope, scopeSet, scopeHas, scopeFork } from 'code_analysis.types.scope';
import { UNKNOWN, STR } from 'code_analysis.types.type_utils';
import { parseGuard, applyGuard } from 'code_analysis.types.narrowing';

// Emit a (offset, scope) checkpoint into the sorted map.
function emit(map, offset, scope) {
    push(map, { offset, scope });
}

// Advance scope for a lexical_declaration, forking once per declarator.
// COW: returns a new scope; does not mutate the input scope.
function forkDecl(stmt, source, uri, scope) {
    let declared = declaredType(stmt, source, uri);
    for (let i = 0; i < ts.namedChildCount(stmt); i++) {
        let decl = ts.namedChild(stmt, i);
        if (ts.nodeType(decl) !== 'variable_declarator') continue;
        let nameNode = ts.childByField(decl, 'name');
        let valNode  = ts.childByField(decl, 'value');
        if (nameNode && ts.nodeType(nameNode) === 'identifier') {
            let t = declared ?? (valNode ? inferNode(valNode, source, uri, scope, 0) : UNKNOWN);
            scope = scopeFork(scope, ts.text(nameNode, source), t);
        }
    }
    return scope;
}

// Advance scope when a statement reassigns an existing binding.
function forkAssign(stmt, source, uri, scope) {
    let inner = firstNamed(stmt);
    if (!inner || ts.nodeType(inner) !== 'assignment_expression') return scope;
    let lhs = ts.childByField(inner, 'left');
    let rhs = ts.childByField(inner, 'right');
    if (!lhs || !rhs || ts.nodeType(lhs) !== 'identifier') return scope;
    let name = ts.text(lhs, source);
    let newType = inferNode(rhs, source, uri, scope, 0);
    if (scopeHas(scope, name) && newType.kind !== 'unknown')
        return scopeFork(scope, name, newType);
    return scope;
}

// Return the scope after processing stmt's own declarations (COW).
function advanceScope(stmt, source, uri, scope) {
    let stype = ts.nodeType(stmt);

    if (stype === 'lexical_declaration')
        return forkDecl(stmt, source, uri, scope);

    if (stype === 'function_declaration') {
        let nameNode = ts.childByField(stmt, 'name');
        if (nameNode && ts.nodeType(nameNode) === 'identifier')
            return scopeFork(scope, ts.text(nameNode, source),
                inferNode(stmt, source, uri, scope, 0));
        return scope;
    }

    if (stype === 'export_statement') {
        let inner = ts.childByField(stmt, 'declaration');
        if (!inner) return scope;
        if (ts.nodeType(inner) === 'lexical_declaration')
            return forkDecl(inner, source, uri, scope);
        if (ts.nodeType(inner) === 'function_declaration') {
            let nameNode = ts.childByField(inner, 'name');
            if (nameNode && ts.nodeType(nameNode) === 'identifier')
                return scopeFork(scope, ts.text(nameNode, source),
                    inferNode(inner, source, uri, scope, 0));
        }
        return scope;
    }

    if (stype === 'expression_statement')
        return forkAssign(stmt, source, uri, scope);

    return scope;
}

// Add params to a fresh scope object (mutable — called before any checkpoint).
function addParams(fn, source, uri, scope) {
    let fnType = inferNode(fn, source, uri, scope, 0);
    if (!fnType || fnType.kind !== 'function') return;
    for (let i = 0; i < length(fnType.params); i++) {
        let p = fnType.params[i];
        scopeSet(scope, p.name, p.type ?? UNKNOWN);
    }
}

// Infer the element type that a for-in loop variable takes from its iterable.
function elemTypeOf(iterType) {
    if (iterType.kind === 'nullable') iterType = iterType.inner;
    if (iterType.kind === 'generic' && iterType.base === 'list' && length(iterType.params) > 0)
        return iterType.params[0];
    if (iterType.kind === 'record' || (iterType.kind === 'generic' && iterType.base === 'dict'))
        return STR;
    return UNKNOWN;
}

// Builtins that never return normally: die() raises, exit() ends the process.
// A statement calling either terminates control just like return/throw.
function isNoReturnCall(node, source) {
    if (!node || ts.nodeType(node) !== 'call_expression') return false;
    let callee = ts.childByField(node, 'function');
    if (!callee || ts.nodeType(callee) !== 'identifier') return false;
    let name = ts.text(callee, source);
    return name === 'die' || name === 'exit';
}

// True when a node unconditionally transfers control out of the block.
function endsInTerminator(node, source) {
    if (!node) return false;
    let nt = ts.nodeType(node);
    if (nt === 'return_statement' || nt === 'break_statement' ||
        nt === 'continue_statement' || nt === 'throw_statement') return true;
    if (nt === 'expression_statement')
        return isNoReturnCall(firstNamed(node), source);
    if (nt === 'statement_block') {
        let stmts = namedNonComments(node);
        return length(stmts) > 0 && endsInTerminator(stmts[-1], source);
    }
    return false;
}

// If stmt is a guard-clause if-statement (no else, terminating body), return
// the scope narrowed by the negated guard; otherwise return scope unchanged.
function applyGuardClause(stmt, source, scope) {
    if (ts.nodeType(stmt) !== 'if_statement') return scope;
    let alt  = ts.childByField(stmt, 'alternative');
    let cons = ts.childByField(stmt, 'consequence');
    if (alt || !cons || !endsInTerminator(cons, source)) return scope;
    let condWrapper = ts.childByField(stmt, 'condition');
    let cond = firstNamed(condWrapper);
    let guard = cond ? parseGuard(cond, source) : null;
    if (!guard) return scope;
    let narrowed = makeScope(scope);
    applyGuard(narrowed, guard, false);
    return narrowed;
}

// Forward declaration so handler functions can call walkNode.
let walkNode;

// Process one statement in a sequential run: emit its checkpoint, walk into it,
// then advance the scope past its own declarations and any guard clause, and
// return the new scope for the following siblings.
//
// Templates need nothing special: a template is one statement stream, so a `let`
// in one tag is simply an earlier statement than the text_statement (and the
// `{{ }}` tags inside it) that follows. The tag delimiters at a template's root
// carry no declarations and walk as no-ops.
function stepStatement(stmt, source, uri, scope, map) {
    emit(map, ts.startByte(stmt), scope);
    walkNode(stmt, source, uri, scope, map);
    scope = advanceScope(stmt, source, uri, scope);
    scope = applyGuardClause(stmt, source, scope);
    return scope;
}

// Walk a statement_block with the given scope as its initial scope.
// The caller is responsible for setting up scope (params, narrowing, etc.)
// before calling; walkBlock handles per-statement checkpointing, declaration
// advancement, and guard-clause narrowing for subsequent siblings.
function walkBlock(block, source, uri, scope, map) {
    emit(map, ts.startByte(block), scope);
    let n = ts.namedChildCount(block);
    for (let i = 0; i < n; i++)
        scope = stepStatement(ts.namedChild(block, i), source, uri, scope, map);
}

function walkIfStmt(node, source, uri, scope, map) {
    let condWrapper = ts.childByField(node, 'condition');
    let consequent  = ts.childByField(node, 'consequence');
    let alt         = ts.childByField(node, 'alternative');
    let cond = firstNamed(condWrapper);
    if (cond) walkNode(cond, source, uri, scope, map);
    let guard = cond ? parseGuard(cond, source) : null;
    let trueScope  = makeScope(scope);
    let falseScope = makeScope(scope);
    applyGuard(trueScope,  guard, true);
    applyGuard(falseScope, guard, false);
    if (consequent) {
        // Emit so a brace-less body (e.g. `if (x !== null) return x.foo;`) sees
        // the narrowed scope; a block body re-emits per-statement inside walkBlock.
        emit(map, ts.startByte(consequent), trueScope);
        walkNode(consequent, source, uri, trueScope, map);
    }
    if (alt) {
        let altBody = firstNamed(alt);
        if (altBody) {
            emit(map, ts.startByte(altBody), falseScope);
            walkNode(altBody, source, uri, falseScope, map);
        }
    }
}

function walkForIn(node, source, uri, scope, map) {
    let right = ts.childByField(node, 'object');
    let left  = ts.childByField(node, 'variable') ?? ts.childByField(node, 'key');
    let body  = ts.childByField(node, 'body');
    if (right) walkNode(right, source, uri, scope, map);
    let loopScope = makeScope(scope);
    if (left && ts.nodeType(left) === 'identifier') {
        let iterType = right ? inferNode(right, source, uri, scope, 0) : UNKNOWN;
        scopeSet(loopScope, ts.text(left, source), elemTypeOf(iterType));
    }
    if (body) walkNode(body, source, uri, loopScope, map);
}

function walkForStmt(node, source, uri, scope, map) {
    let init = ts.childByField(node, 'initializer');
    let cond = ts.childByField(node, 'condition');
    let incr = ts.childByField(node, 'increment');
    let body = ts.childByField(node, 'body');
    // Initializer variables are added to a fresh scope before any checkpoint.
    let forScope = makeScope(scope);
    if (init && ts.nodeType(init) === 'lexical_declaration') {
        for (let i = 0; i < ts.namedChildCount(init); i++) {
            let decl = ts.namedChild(init, i);
            if (ts.nodeType(decl) !== 'variable_declarator') continue;
            let nameNode = ts.childByField(decl, 'name');
            let valNode  = ts.childByField(decl, 'value');
            if (nameNode && ts.nodeType(nameNode) === 'identifier') {
                let t = valNode ? inferNode(valNode, source, uri, forScope, 0) : UNKNOWN;
                scopeSet(forScope, ts.text(nameNode, source), t);
            }
        }
    }
    if (cond) walkNode(cond, source, uri, forScope, map);
    if (incr) walkNode(incr, source, uri, forScope, map);
    if (body) walkNode(body, source, uri, forScope, map);
}

// ── colon / end… (alt-syntax) forms: `for (…): … endfor` and friends ────────────
// These mirror the brace-form walkers. Their body is a statement_list (absent
// when the body is empty) rather than a statement_block, threaded statement by
// statement through stepStatement. In a template the same nodes span tags
// ({% for (x in xs): %}…{% endfor %}): the text between the tags is just another
// statement (a text_statement) in that list. Brace-bodied forms that span tags
// ({% if (c) { %}…{% } %}) need nothing here at all — they are ordinary
// if_statement / statement_block nodes.

// Thread every statement of a statement_list under the given scope, so a
// `{% let %}` inside the body flows to later statements and nested spanning
// forms recurse correctly.
function walkStatementList(list, source, uri, scope, map) {
    if (!list) return;
    for (let i = 0; i < ts.namedChildCount(list); i++)
        scope = stepStatement(ts.namedChild(list, i), source, uri, scope, map);
}

// {% for (x in xs): %} … {% endfor %} — mirror walkForIn's loop-var binding.
function walkForInAlt(node, source, uri, scope, map) {
    let right = ts.childByField(node, 'object');
    let left  = ts.childByField(node, 'variable') ?? ts.childByField(node, 'key');
    if (right) walkNode(right, source, uri, scope, map);
    let loopScope = makeScope(scope);
    if (left && ts.nodeType(left) === 'identifier') {
        let iterType = right ? inferNode(right, source, uri, scope, 0) : UNKNOWN;
        scopeSet(loopScope, ts.text(left, source), elemTypeOf(iterType));
    }
    walkStatementList(ts.childByField(node, 'body'), source, uri, loopScope, map);
}

// {% for (init; cond; incr): %} … {% endfor %} — mirror walkForStmt.
function walkForAlt(node, source, uri, scope, map) {
    let init = ts.childByField(node, 'initializer');
    let cond = ts.childByField(node, 'condition');
    let incr = ts.childByField(node, 'increment');
    let forScope = makeScope(scope);
    if (init && ts.nodeType(init) === 'lexical_declaration') {
        for (let i = 0; i < ts.namedChildCount(init); i++) {
            let decl = ts.namedChild(init, i);
            if (ts.nodeType(decl) !== 'variable_declarator') continue;
            let nameNode = ts.childByField(decl, 'name');
            let valNode  = ts.childByField(decl, 'value');
            if (nameNode && ts.nodeType(nameNode) === 'identifier') {
                let t = valNode ? inferNode(valNode, source, uri, forScope, 0) : UNKNOWN;
                scopeSet(forScope, ts.text(nameNode, source), t);
            }
        }
    }
    if (cond) walkNode(cond, source, uri, forScope, map);
    if (incr) walkNode(incr, source, uri, forScope, map);
    walkStatementList(ts.childByField(node, 'body'), source, uri, forScope, map);
}

// {% while (cond): %} … {% endwhile %}. Walk the condition, then thread the body
// under the current scope (a loop condition implies no lasting narrowing).
function walkWhileAlt(node, source, uri, scope, map) {
    let condWrapper = ts.childByField(node, 'condition');
    if (condWrapper)
        walkNode(firstNamed(condWrapper) ?? condWrapper, source, uri, scope, map);
    walkStatementList(ts.childByField(node, 'body'), source, uri, scope, map);
}

// `if (cond): … elif (c2): … else: … endif` — in a template, {% if (cond): %} …
// {% elif (c2): %} … {% else %} … {% endif %}. The if-branch body is the
// `consequence` statement_list; the elif/else branches are `elif_clause` /
// `else_alt_clause` nodes that each CONTAIN their own condition and body. Walk
// each body under the scope narrowed by that branch's guard: the
// if/elif bodies see their condition as true; the else body sees the if condition
// as false. We omit the cumulative negation of earlier conditions in elif/else
// branches — that only ever narrows *less*, never incorrectly. Declarations thread
// within a branch and reset at each boundary (branches are independent control flow).
function walkIfAlt(node, source, uri, scope, map) {
    let condWrapper = ts.childByField(node, 'condition');
    let ifCond = firstNamed(condWrapper);
    if (ifCond) walkNode(ifCond, source, uri, scope, map);
    let ifGuard = ifCond ? parseGuard(ifCond, source) : null;

    let branch = makeScope(scope);
    applyGuard(branch, ifGuard, true);
    walkStatementList(ts.childByField(node, 'consequence'), source, uri, branch, map);

    for (let i = 0; i < ts.namedChildCount(node); i++) {
        let child = ts.namedChild(node, i);
        let ct = ts.nodeType(child);
        if (ct !== 'elif_clause' && ct !== 'else_alt_clause') continue;
        // Narrow a fresh branch by the clause's guard and thread its body
        // through stepStatement, so each body offset gets its own checkpoint —
        // walking it bare would leave those offsets resolving to the previous
        // branch's (if-branch) checkpoint and its narrowing.
        let truthy = (ct === 'elif_clause');
        let guard  = ifGuard;   // else: if-condition false
        let body;
        if (truthy) {
            let ec = ts.childByField(child, 'condition');
            let ecInner = firstNamed(ec);
            if (ecInner) walkNode(ecInner, source, uri, scope, map);
            guard = ecInner ? parseGuard(ecInner, source) : null;
            body = ts.childByField(child, 'consequence');
        } else {
            body = firstNamed(child);   // else_alt_clause: its statement_list, if any
        }
        let inlineBranch = makeScope(scope);
        applyGuard(inlineBranch, guard, truthy);
        walkStatementList(body, source, uri, inlineBranch, map);
    }
}

function walkTry(node, source, uri, scope, map) {
    let body    = ts.childByField(node, 'body');
    let handler = ts.childByField(node, 'handler');
    if (body) walkBlock(body, source, uri, makeScope(scope), map);
    if (handler) {
        let param     = ts.childByField(handler, 'parameter');
        let catchBody = ts.childByField(handler, 'body');
        let catchScope = makeScope(scope);
        if (param && ts.nodeType(param) === 'identifier')
            scopeSet(catchScope, ts.text(param, source), STR);
        if (catchBody) walkBlock(catchBody, source, uri, catchScope, map);
    }
}

function walkFn(node, source, uri, scope, map) {
    let fnScope = makeScope(scope);
    addParams(node, source, uri, fnScope);
    let body = ts.childByField(node, 'body');
    if (!body) return;
    if (ts.nodeType(body) === 'statement_block') {
        walkBlock(body, source, uri, fnScope, map);
    } else if (ts.nodeType(body) === 'statement_list') {
        // Colon form `function f(a): … endfunction` — in a template,
        // {% function f(a): %}…{% endfunction %}.
        walkStatementList(body, source, uri, fnScope, map);
    } else {
        // Arrow function with expression body: emit one checkpoint then recurse.
        emit(map, ts.startByte(body), fnScope);
        walkNode(body, source, uri, fnScope, map);
    }
}

function walkTernary(node, source, uri, scope, map) {
    let cond = ts.childByField(node, 'condition');
    let cons = ts.childByField(node, 'consequence');
    let alt  = ts.childByField(node, 'alternative');
    if (cond) walkNode(cond, source, uri, scope, map);
    let guard = cond ? parseGuard(cond, source) : null;
    let trueScope  = makeScope(scope);
    let falseScope = makeScope(scope);
    applyGuard(trueScope,  guard, true);
    applyGuard(falseScope, guard, false);
    if (cons) {
        emit(map, ts.startByte(cons), trueScope);
        walkNode(cons, source, uri, trueScope,  map);
    }
    if (alt) {
        emit(map, ts.startByte(alt), falseScope);
        walkNode(alt,  source, uri, falseScope, map);
    }
}

function walkBinary(node, source, uri, scope, map) {
    let op    = ts.nodeType(ts.childByField(node, 'operator'));
    let left  = ts.childByField(node, 'left');
    let right = ts.childByField(node, 'right');
    if (left) walkNode(left, source, uri, scope, map);
    if (right) {
        // The RHS of && is reached only when the LHS is truthy; the RHS of ||
        // only when the LHS is falsy. Narrow the RHS scope accordingly so that,
        // e.g., `x && x.foo` and `x === null || x.foo` both see x as non-null.
        if (op === '&&' || op === '||') {
            let guard = left ? parseGuard(left, source) : null;
            if (guard) {
                let rightScope = makeScope(scope);
                applyGuard(rightScope, guard, op === '&&');
                emit(map, ts.startByte(right), rightScope);
                walkNode(right, source, uri, rightScope, map);
            } else {
                walkNode(right, source, uri, scope, map);
            }
        } else {
            walkNode(right, source, uri, scope, map);
        }
    }
}

walkNode = function(node, source, uri, scope, map) {
    let nt = ts.nodeType(node);
    if (nt === 'statement_block') {
        // Standalone block: new scope layer for its own declarations.
        walkBlock(node, source, uri, makeScope(scope), map);
    } else if (nt === 'statement_list') {
        // An alt-syntax body reached without its statement (normally the
        // statement's walker threads it): like a block.
        walkStatementList(node, source, uri, makeScope(scope), map);
    } else if (nt === 'if_statement') {
        walkIfStmt(node, source, uri, scope, map);
    } else if (nt === 'for_in_statement') {
        walkForIn(node, source, uri, scope, map);
    } else if (nt === 'for_statement') {
        walkForStmt(node, source, uri, scope, map);
    } else if (nt === 'for_in_alt_statement') {
        walkForInAlt(node, source, uri, scope, map);
    } else if (nt === 'for_alt_statement') {
        walkForAlt(node, source, uri, scope, map);
    } else if (nt === 'while_alt_statement') {
        walkWhileAlt(node, source, uri, scope, map);
    } else if (nt === 'if_alt_statement') {
        walkIfAlt(node, source, uri, scope, map);
    } else if (nt === 'while_statement') {
        let cond = ts.childByField(node, 'condition');
        let body = ts.childByField(node, 'body');
        if (cond) walkNode(firstNamed(cond) ?? cond, source, uri, scope, map);
        if (body) walkNode(body, source, uri, scope, map);
    } else if (nt === 'try_statement') {
        walkTry(node, source, uri, scope, map);
    } else if (nt === 'function_declaration' || nt === 'function_expression' || nt === 'arrow_function') {
        walkFn(node, source, uri, scope, map);
    } else if (nt === 'ternary_expression') {
        walkTernary(node, source, uri, scope, map);
    } else if (nt === 'binary_expression') {
        walkBinary(node, source, uri, scope, map);
    } else {
        for (let i = 0; i < ts.namedChildCount(node); i++)
            walkNode(ts.namedChild(node, i), source, uri, scope, map);
    }
};

// Build a sorted [(offset, scope)] map for the whole file.
// Checkpoints are emitted before each statement, so scopeAtOffset(map, X)
// returns the scope with all declarations from statements that begin before X.
export function buildScopeMap(uri, source, tree) {
    let root  = ts.rootNode(tree);
    let scope = importScope(uri);
    let map   = [];
    emit(map, 0, scope);
    let n = ts.namedChildCount(root);
    for (let i = 0; i < n; i++)
        scope = stepStatement(ts.namedChild(root, i), source, uri, scope, map);
    // Emit a final checkpoint so lookups past the last statement see its declarations
    // — unless that statement runs to the end with an error (blocks left open at
    // EOF, closed by MISSING `}`): the end of the file is still inside its blocks.
    let last = n ? ts.namedChild(root, n - 1) : null;
    if (!last || !ts.hasError(last) || ts.endByte(last) < ts.endByte(root))
        emit(map, ts.endByte(root), scope);
    return map;
};

// Binary search: return the scope for the largest checkpoint.offset <= offset.
export function scopeAtOffset(map, offset) {
    let lo = 0;
    let hi = length(map) - 1;
    let result = length(map) > 0 ? map[0].scope : makeScope(null);
    while (lo <= hi) {
        let mid = int((lo + hi) / 2);
        if (map[mid].offset <= offset) {
            result = map[mid].scope;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return result;
};
