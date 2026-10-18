import * as ts from 'tree_sitter';
import { firstNamed, namedNonComments, declarators } from 'ucode_analyzer.code_analysis.ast_text';
import { inferNode, inferParams, declaredType, setReturnScopes } from 'ucode_analyzer.code_analysis.types.inferrer';
import { importScope } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { makeScope, scopeSet, scopeGet, scopeHas, scopeFork } from 'ucode_analyzer.code_analysis.types.scope';
import { UNKNOWN, STR, unionOf } from 'ucode_analyzer.code_analysis.types.type_utils';
import { parseGuard, applyGuard as narrowBy, narrowToNonNull, optionalChainRoot } from 'ucode_analyzer.code_analysis.types.narrowing';

// Where the last lookup landed. Passes read a file front to back, so the next
// lookup is usually at that checkpoint or a few past it.
let _hintMap = null, _hintAt = 0;

// The scope of the largest checkpoint.offset <= offset (the first checkpoint's
// before any).
export function scopeAtOffset(map, offset) {
    let n = length(map);
    if (n === 0) return makeScope(null);
    let i = (_hintMap === map && _hintAt < n) ? _hintAt : 0;
    if (map[i].offset <= offset) {
        for (let k = 0; k < 8 && i + 1 < n && map[i + 1].offset <= offset; k++) i++;
        if (i + 1 < n && map[i + 1].offset <= offset) i = -1;   // further on: search
    } else {
        i = -1;
    }
    if (i < 0) {
        let lo = 0, hi = n - 1;
        i = 0;
        while (lo <= hi) {
            let mid = (lo + hi) >> 1;
            if (map[mid].offset <= offset) { i = mid; lo = mid + 1; }
            else hi = mid - 1;
        }
    }
    _hintMap = map;
    _hintAt = i;
    return map[i].scope;
};

// The checkpoint with the largest offset <= offset, or null.
function checkpointAt(map, offset) {
    let lo = 0, hi = length(map) - 1, found = null;
    while (lo <= hi) {
        let mid = (lo + hi) >> 1;
        if (map[mid].offset <= offset) { found = map[mid]; lo = mid + 1; }
        else hi = mid - 1;
    }
    return found;
}

// Emit a (offset, scope) checkpoint into the sorted map.
function emit(map, offset, scope) {
    push(map, { offset, scope });
}

// Variables declared from an optional chain (`let code = body?.status?.code`),
// by name: the chain's root variable. Where a guard proves one non-null, its
// root is non-null too. Matched by name: that can only hide a finding.
let _chainRoots = {};

function rootsNonNull(scope, guard, positive) {
    if (!guard) return;
    if (guard.kind === 'and' || guard.kind === 'or') {
        if (positive === (guard.kind === 'and'))
            for (let g in guard.guards) rootsNonNull(scope, g, positive);
        return;
    }
    let root = _chainRoots[guard.name];
    if (guard.kind !== 'truthy' || !root || !scopeHas(scope, root)) return;
    if (guard.positive ? positive : !positive)
        scopeSet(scope, root, narrowToNonNull(scopeGet(scope, root) ?? UNKNOWN));
}

// As narrowing's applyGuard, also narrowing the chain roots of the variables
// the guard proves non-null.
function applyGuard(scope, guard, positive) {
    narrowBy(scope, guard, positive);
    rootsNonNull(scope, guard, positive);
}

// Advance scope for a lexical_declaration, forking once per declarator.
// COW: returns a new scope; does not mutate the input scope.
function forkDecl(stmt, source, uri, scope) {
    let declared = declaredType(stmt, source, uri);
    for (let decl in declarators(stmt)) {
        let nameNode = ts.childByField(decl, 'name');
        let valNode  = ts.childByField(decl, 'value');
        if (nameNode && ts.nodeType(nameNode) === 'identifier') {
            let root = valNode ? optionalChainRoot(valNode, source) : null;
            if (root) _chainRoots[ts.text(nameNode, source)] = root;
            let t = declared ?? (valNode ? inferNode(valNode, source, uri, scope, 0) : UNKNOWN);
            scope = scopeFork(scope, ts.text(nameNode, source), t);
        }
    }
    return scope;
}

// The union of types, or UNKNOWN when any is unknown (stay silent, not guess).
function joinTypes(types) {
    let flat = [];
    for (let t in types) {
        if (!t || t.kind === 'unknown') return UNKNOWN;
        if (t.kind === 'union') push(flat, ...t.members); else push(flat, t);
    }
    return unionOf(flat);
}

// The operators that assign only when the variable is null (or falsy).
const FILLS = { '??=': true, '||=': true };

// The type of x after `x ??= v` or `x ||= v`: its non-null part, or v's type.
function filledType(old, v) {
    if (old.kind === 'primitive' && old.name === 'null') return v;
    return joinTypes([narrowToNonNull(old), v]);
}

// Advance scope when a statement reassigns an existing binding.
function forkAssign(stmt, source, uri, scope) {
    let inner = firstNamed(stmt);
    let it = inner ? ts.nodeType(inner) : null;
    if (it !== 'assignment_expression' && it !== 'augmented_assignment_expression') return scope;
    let lhs = ts.childByField(inner, 'left');
    let rhs = ts.childByField(inner, 'right');
    if (!lhs || !rhs || ts.nodeType(lhs) !== 'identifier') return scope;
    let name = ts.text(lhs, source);
    if (!scopeHas(scope, name)) return scope;
    let newType = inferNode(rhs, source, uri, scope, 0);
    if (it === 'augmented_assignment_expression') {
        let op = ts.childByField(inner, 'operator');
        if (!op || !FILLS[ts.nodeType(op)]) return scope;
        newType = filledType(scopeGet(scope, name) ?? UNKNOWN, newType);
    }
    return scopeFork(scope, name, newType);
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
    for (let p in inferParams(fn, source, uri, scope))
        scopeSet(scope, p.name, p.type ?? UNKNOWN);
}

// `for (k, v in it)`: the key is an index for a list, a string for a dict.
function keyTypeOf(iterType) {
    if (iterType.kind === 'nullable') iterType = iterType.inner;
    if (iterType.kind === 'generic' && iterType.base === 'list') return { kind: 'primitive', name: 'int' };
    if (iterType.kind === 'record' || (iterType.kind === 'generic' && iterType.base === 'dict')) return STR;
    return UNKNOWN;
}

// `for (k, v in it)`: the value is a list item or a dict value.
function valueTypeOf(iterType) {
    if (iterType.kind === 'nullable') iterType = iterType.inner;
    if (iterType.kind === 'generic' && length(iterType.params) > 0)
        return iterType.base === 'dict' ? (iterType.params[-1] ?? UNKNOWN) : iterType.params[0];
    return UNKNOWN;
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

// ── Assignment widening ───────────────────────────────────────────────────
// After a compound statement, a variable it assigns has the type of whichever
// path reached the end: `let x = null; if (c) x = {};` leaves x `null | {}`.

// One pass for both: patterns 0 and 1 are assignments (`??=` and `||=` widen
// like `=`), the others declarations.
let BINDINGS = `
(assignment_expression left: (identifier) @name right: (_) @rhs)
(augmented_assignment_expression left: (identifier) @name operator: ["??=" "||="] right: (_) @rhs)
(variable_declarator name: (identifier) @name)
(for_in_statement variable: (identifier) @name)`;
let _queries = {};

function query(lang) {
    _queries[lang] ??= ts.newQuery(lang === 'markup' ? ts.markup() : ts.ucode(), BINDINGS);
    return _queries[lang];
}

const FUNCTION_TYPES = { function_declaration: true, function_expression: true, arrow_function: true };

// Index of the first entry of a start-sorted list at or after `start`.
function lowerBound(list, start) {
    let lo = 0, hi = length(list);
    while (lo < hi) {
        let mid = (lo + hi) >> 1;
        if (list[mid].start < start) lo = mid + 1; else hi = mid;
    }
    return lo;
}

// Every `name = …` and every declared name of the tree being mapped, sorted by
// start, collected once: { start, name, rhs, fnStart, fnEnd } with fnStart and
// fnEnd the range of the innermost enclosing function (-1 at top level).
// _captured holds the right-hand sides, by name, of the variables another
// function may see change (see widenCaptured); _capturedType caches its joins.
let _assigns = [], _decls = [], _captured = {}, _capturedType = {};

function collectBindings(root, source) {
    let lang = ts.nodeType(root) === 'markup' ? 'markup' : 'ucode';
    _assigns = [];
    _decls = [];
    _captured = {};
    _capturedType = {};
    let fns = ts.descendantOffsets(root, keys(FUNCTION_TYPES));
    let firstFn = length(fns) ? fns[0] : -1;
    for (let m in ts.queryMatches(query(lang), root, source)) {
        let c = {};
        for (let cap in m.captures) c[cap.name] = cap.node;
        let entry = { start: ts.startByte(c.name), name: ts.text(c.name, source) };
        if (m.pattern > 1) { push(_decls, entry); continue; }
        entry.rhs = c.rhs;
        entry.fnStart = entry.fnEnd = -1;
        for (let p = ts.parent(c.name); p; p = ts.parent(p))
            if (FUNCTION_TYPES[ts.nodeType(p)]) { entry.fnStart = ts.startByte(p); entry.fnEnd = ts.endByte(p); break; }
        push(_assigns, entry);
    }
    // Captured: assigned in a function that does not declare it (the variable is
    // an enclosing one), or at top level once a function exists that can run
    // later. A variable assigned only where it is declared, before any function,
    // reads the same from every function, and the walk tracks it in order.
    for (let a in _assigns) {
        let local = false;
        if (a.fnStart >= 0)
            for (let i = lowerBound(_decls, a.fnStart); i < length(_decls) && _decls[i].start < a.fnEnd; i++)
                if (_decls[i].name === a.name) { local = true; break; }
        let captured = (a.fnStart >= 0) ? !local : (firstFn >= 0 && a.start > firstFn);
        if (!captured) continue;
        _captured[a.name] ??= [];
        push(_captured[a.name], a.rhs);
    }
}


// { name: [rhs nodes] } for `name = …` inside stmt, outside functions nested
// in it, for names stmt does not declare itself.
function assignmentsIn(stmt, source) {
    let s = ts.startByte(stmt), e = ts.endByte(stmt);
    let out = {};
    for (let i = lowerBound(_assigns, s); i < length(_assigns) && _assigns[i].start < e; i++) {
        let a = _assigns[i];
        if (a.fnStart >= s) continue;   // inside a function nested in stmt
        out[a.name] ??= [];
        push(out[a.name], a.rhs);
    }
    if (length(out))
        for (let i = lowerBound(_decls, s); i < length(_decls) && _decls[i].start < e; i++)
            delete out[_decls[i].name];
    return out;
}

function rhsType(rhs, source, uri, smap) {
    return inferNode(rhs, source, uri, scopeAtOffset(smap, ts.startByte(rhs)), 0);
}

function entryType(scope, name, guard, positive) {
    if (!guard) return scopeGet(scope, name) ?? UNKNOWN;
    let s = makeScope(scope);
    applyGuard(s, guard, positive);
    return scopeGet(s, name) ?? UNKNOWN;
}

// branchExit and ifExit recurse into each other (ucode does not hoist).
let ifExit;

// Type of `name` leaving a branch entered with `t`, or null when the branch
// cannot fall out (ends in return/break/…). Direct assignments in the
// branch's own statements are tracked in order; any deeper one widens.
let branchExit;
branchExit = function(branch, name, t, source, uri, smap) {
    let bt = ts.nodeType(branch);
    if (bt === 'if_statement') return ifExit(branch, name, t, source, uri, smap);
    let stmts = (bt === 'statement_block' || bt === 'statement_list') ? namedNonComments(branch) : [branch];
    if (length(stmts) && endsInTerminator(stmts[-1], source)) return null;
    for (let st in stmts) {
        let e = (ts.nodeType(st) === 'expression_statement') ? firstNamed(st) : null;
        if (e && ts.nodeType(e) === 'assignment_expression') {
            let l = ts.childByField(e, 'left');
            if (l && ts.nodeType(l) === 'identifier' && ts.text(l, source) === name) {
                t = rhsType(ts.childByField(e, 'right'), source, uri, smap);
                continue;
            }
        }
        if (ts.nodeType(st) === 'if_statement') {
            t = ifExit(st, name, t, source, uri, smap);
            if (t === null) return null;   // every branch of it ends the flow
            continue;
        }
        let deeper = assignmentsIn(st, source)[name];
        if (deeper) t = joinTypes([t, ...map(deeper, (r) => rhsType(r, source, uri, smap))]);
    }
    return t;
};

// Type of `name` after an if/else chain entered with `t`; null when every
// branch ends the flow.
ifExit = function(node, name, t, source, uri, smap) {
    let cond  = firstNamed(ts.childByField(node, 'condition'));
    let guard = cond ? parseGuard(cond, source) : null;
    let exits = [];
    let scopeT = makeScope(null);
    scopeSet(scopeT, name, t);
    let cons = ts.childByField(node, 'consequence');
    let e1 = cons ? branchExit(cons, name, entryType(scopeT, name, guard, true), source, uri, smap) : null;
    if (e1 !== null) push(exits, e1);
    let alt = ts.childByField(node, 'alternative');
    let falseT = entryType(scopeT, name, guard, false);
    if (alt) {
        let altBody = firstNamed(alt);
        let e2 = altBody ? branchExit(altBody, name, falseT, source, uri, smap) : falseT;
        if (e2 !== null) push(exits, e2);
    } else {
        push(exits, falseT);
    }
    return length(exits) ? joinTypes(exits) : null;
};

const LOOP_LIKE = {
    while_statement: true, for_statement: true, for_in_statement: true,
    for_alt_statement: true, for_in_alt_statement: true, while_alt_statement: true,
    if_alt_statement: true, switch_statement: true, try_statement: true,
};

// The scope after a compound statement, with every outer variable it assigns
// widened to the types that can reach its end.
function widenAssigned(stmt, before, after, source, uri, smap) {
    let st = ts.nodeType(stmt);
    if (st !== 'if_statement' && !LOOP_LIKE[st]) return after;
    let assigned = assignmentsIn(stmt, source);
    for (let name, rhss in assigned) {
        if (!scopeHas(before, name)) continue;
        let t0 = scopeGet(before, name) ?? UNKNOWN;
        let t = (st === 'if_statement')
            ? ifExit(stmt, name, t0, source, uri, smap)
            : joinTypes([t0, ...map(rhss, (r) => rhsType(r, source, uri, smap))]);
        if (t !== null) after = scopeFork(after, name, t);
    }
    return after;
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
    let inner = length(map);
    walkNode(stmt, source, uri, scope, map);
    inner = length(map) > inner;
    let next = applyGuardClause(stmt, source, advanceScope(stmt, source, uri, scope));
    next = widenAssigned(stmt, scope, next, source, uri, map);
    // Past the statement's end (a blank line before the next one) its
    // declarations are in scope and its blocks' are not. Not when it is left
    // open at EOF: the end of the file is still inside its blocks.
    if ((next !== scope || inner) && !(ts.hasError(stmt) && ts.endByte(stmt) >= length(source)))
        emit(map, ts.endByte(stmt), next);
    return next;
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

// The scope of a for-in body, in either syntax: `for (x in xs)` binds x to
// the element; `for (k, v in o)` binds k to the key and v to the value.
function forInScope(node, source, uri, scope) {
    let right = ts.childByField(node, 'object');
    let left  = ts.childByField(node, 'variable') ?? ts.childByField(node, 'key');
    let value = ts.childByField(node, 'value');
    let loopScope = makeScope(scope);
    let iterType = right ? inferNode(right, source, uri, scope, 0) : UNKNOWN;
    if (left && ts.nodeType(left) === 'identifier')
        scopeSet(loopScope, ts.text(left, source), value ? keyTypeOf(iterType) : elemTypeOf(iterType));
    if (value && ts.nodeType(value) === 'identifier')
        scopeSet(loopScope, ts.text(value, source), valueTypeOf(iterType));
    return loopScope;
}

function walkForIn(node, source, uri, scope, map) {
    let right = ts.childByField(node, 'object');
    let body  = ts.childByField(node, 'body');
    if (right) walkNode(right, source, uri, scope, map);
    let loopScope = forInScope(node, source, uri, scope);
    if (body) {
        emit(map, ts.startByte(body), loopScope);
        walkNode(body, source, uri, loopScope, map);
    }
}

// The scope of a loop body: the condition, checked before every iteration,
// holds there. Not after the loop, which a break can leave.
function loopBodyScope(cond, source, scope) {
    let guard = cond ? parseGuard(cond, source) : null;
    if (!guard) return scope;
    let s = makeScope(scope);
    applyGuard(s, guard, true);
    return s;
}

function walkForStmt(node, source, uri, scope, map) {
    let init = ts.childByField(node, 'initializer');
    let cond = ts.childByField(node, 'condition');
    let incr = ts.childByField(node, 'increment');
    let body = ts.childByField(node, 'body');
    // Initializer variables are added to a fresh scope before any checkpoint.
    let forScope = makeScope(scope);
    if (init && ts.nodeType(init) === 'lexical_declaration') {
        for (let decl in declarators(init)) {
            let nameNode = ts.childByField(decl, 'name');
            let valNode  = ts.childByField(decl, 'value');
            if (nameNode && ts.nodeType(nameNode) === 'identifier') {
                let t = valNode ? inferNode(valNode, source, uri, forScope, 0) : UNKNOWN;
                scopeSet(forScope, ts.text(nameNode, source), t);
            }
        }
    }
    // The increment runs only after a true condition, which the scope cannot
    // express (`l = f.read()` with `l` derived from `f?.read()`): its offsets
    // keep the scope before the loop, as they always did.
    if (cond) { emit(map, ts.startByte(cond), forScope); walkNode(cond, source, uri, forScope, map); }
    if (incr) { emit(map, ts.startByte(incr), scope); walkNode(incr, source, uri, forScope, map); }
    let bodyScope = loopBodyScope(cond, source, forScope);
    if (body) { emit(map, ts.startByte(body), bodyScope); walkNode(body, source, uri, bodyScope, map); }
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

// {% for (x in xs): %} … {% endfor %}
function walkForInAlt(node, source, uri, scope, map) {
    let right = ts.childByField(node, 'object');
    if (right) walkNode(right, source, uri, scope, map);
    walkStatementList(ts.childByField(node, 'body'), source, uri, forInScope(node, source, uri, scope), map);
}

// {% for (init; cond; incr): %} … {% endfor %} — mirror walkForStmt.
function walkForAlt(node, source, uri, scope, map) {
    let init = ts.childByField(node, 'initializer');
    let cond = ts.childByField(node, 'condition');
    let incr = ts.childByField(node, 'increment');
    let forScope = makeScope(scope);
    if (init && ts.nodeType(init) === 'lexical_declaration') {
        for (let decl in declarators(init)) {
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
    walkStatementList(ts.childByField(node, 'body'), source, uri, loopBodyScope(cond, source, forScope), map);
}

// {% while (cond): %} … {% endwhile %}. Walk the condition, then thread the body
// under it (a loop condition implies no lasting narrowing).
function walkWhileAlt(node, source, uri, scope, map) {
    let condWrapper = ts.childByField(node, 'condition');
    let cond = condWrapper ? (firstNamed(condWrapper) ?? condWrapper) : null;
    if (cond) walkNode(cond, source, uri, scope, map);
    walkStatementList(ts.childByField(node, 'body'), source, uri, loopBodyScope(cond, source, scope), map);
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

// What `catch (e)` binds: the exception object, whatever die() was given as
// its message (it prints as that message).
const EXCEPTION = { kind: 'record', fields: [
    { name: 'type',       type: STR },
    { name: 'message',    type: UNKNOWN },
    { name: 'stacktrace', type: { kind: 'generic', base: 'list', params: [UNKNOWN] } },
] };

function walkTry(node, source, uri, scope, map) {
    let body    = ts.childByField(node, 'body');
    let handler = ts.childByField(node, 'handler');
    if (body) walkBlock(body, source, uri, makeScope(scope), map);
    if (handler) {
        let param     = ts.childByField(handler, 'parameter');
        let catchBody = ts.childByField(handler, 'body');
        let catchScope = makeScope(scope);
        if (param && ts.nodeType(param) === 'identifier')
            scopeSet(catchScope, ts.text(param, source), EXCEPTION);
        if (catchBody) walkBlock(catchBody, source, uri, catchScope, map);
    }
}

// The variable a switch subject proves non-null when it equals a non-null
// literal: `x` for `switch (x)`, `X` for `switch (X?.p)` / `switch (X?.[i])`.
function switchSubject(value, source) {
    let t = ts.nodeType(value);
    if (t === 'identifier') return ts.text(value, source);
    if ((t === 'member_expression' || t === 'subscript_expression') &&
        ts.childByField(value, 'optional_chain')) {
        let obj = ts.childByField(value, 'object');
        if (obj && ts.nodeType(obj) === 'identifier') return ts.text(obj, source);
    }
    return null;
}

const NON_NULL_LITERALS = { string: true, template_string: true, number: true, 'true': true, 'false': true };

// Each clause threads its statements; declarations carry into the next clause
// when control falls through. A clause whose label is a non-null literal sees
// the subject as non-null, unless the clause before it can fall into it
// without that guarantee (default, or an un-narrowed clause).
function walkSwitch(node, source, uri, scope, map) {
    let valueWrap = ts.childByField(node, 'value');
    let value = firstNamed(valueWrap) ?? valueWrap;
    if (value) walkNode(value, source, uri, scope, map);
    let subject = value ? switchSubject(value, source) : null;
    let body = ts.childByField(node, 'body');
    if (!body) return;
    let bodyScope = makeScope(scope);
    let prevEnd = null, prevFalls = false, prevNarrowed = false;
    for (let clause in ts.namedChildren(body)) {
        let ct = ts.nodeType(clause);
        if (ct !== 'switch_case' && ct !== 'switch_default') continue;
        let label = ts.childByField(clause, 'value');
        let narrow = subject !== null && label !== null && NON_NULL_LITERALS[ts.nodeType(label)] === true
                     && (!prevFalls || prevNarrowed);
        let s = (prevFalls && (narrow || !prevNarrowed)) ? prevEnd : bodyScope;
        if (narrow) {
            s = makeScope(s);
            applyGuard(s, { kind: 'truthy', name: subject, positive: true }, true);
        }
        emit(map, ts.startByte(clause), s);
        let stmts = filter(namedNonComments(clause), (c) => !label || ts.startByte(c) !== ts.startByte(label));
        for (let stmt in stmts)
            s = stepStatement(stmt, source, uri, s, map);
        prevEnd = s;
        prevFalls = !length(stmts) || !endsInTerminator(stmts[-1], source);
        prevNarrowed = narrow;
    }
}

// A function body can run after any assignment in the file, so inside it an
// outer variable the file assigns may hold any of the assigned types: `let x =
// null; function init() { x = {}; }` makes x `null | object` in every function
// that mentions it. Matched by name, so a shadowing variable only widens, never
// narrows. The widened types go in the function's own frame (fnScope), not in a
// chain of forks every later lookup would walk.
function widenCaptured(fnScope, body, source, uri, smap) {
    let text = ts.text(body, source);
    for (let name, rhss in _captured) {
        if (index(text, name) < 0) continue;
        let t0 = scopeGet(fnScope, name);
        if (!t0 || t0.kind === 'unknown') continue;
        _capturedType[name] ??= joinTypes(map(rhss, (r) => rhsType(r, source, uri, smap)));
        scopeSet(fnScope, name, joinTypes([t0, _capturedType[name]]));
    }
}

function walkFn(node, source, uri, scope, map) {
    let fnScope = makeScope(scope);
    let body = ts.childByField(node, 'body');
    if (body) widenCaptured(fnScope, body, source, uri, map);
    addParams(node, source, uri, fnScope);
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

// The node types walkNode handles itself; everything else only recurses, so a
// subtree holding none of them emits nothing and is skipped. Keep in sync
// with walkNode's dispatch.
const SCOPE_TYPES = [
    'statement_block', 'statement_list', 'if_statement', 'for_in_statement',
    'for_statement', 'for_in_alt_statement', 'for_alt_statement',
    'while_alt_statement', 'if_alt_statement', 'while_statement',
    'try_statement', 'function_declaration', 'function_expression',
    'arrow_function', 'ternary_expression', 'binary_expression',
    'switch_statement',
];

// Start bytes of the SCOPE_TYPES nodes in the tree being mapped, sorted; null
// outside buildScopeMap (then nothing is skipped). _pos is the first mark at
// or after the last queried start: the walk queries in source order, so it
// moves forward; a query behind it falls back to a binary search.
let _marks = null, _pos = 0;

// Does [start, end) hold the start of a SCOPE_TYPES node? Without marks,
// assume it does: nothing is skipped.
function holdsMark(start, end) {
    if (!_marks) return true;
    if (_pos > 0 && _marks[_pos - 1] >= start) {
        let lo = 0, hi = _pos;
        while (lo < hi) {
            let mid = (lo + hi) >> 1;
            if (_marks[mid] < start) lo = mid + 1; else hi = mid;
        }
        _pos = lo;
    }
    let n = length(_marks);
    while (_pos < n && _marks[_pos] < start) _pos++;
    return _pos < n && _marks[_pos] < end;
}

function walkWhile(node, source, uri, scope, map) {
    let wrapper = ts.childByField(node, 'condition');
    let cond = wrapper ? (firstNamed(wrapper) ?? wrapper) : null;
    let body = ts.childByField(node, 'body');
    if (cond) walkNode(cond, source, uri, scope, map);
    if (body) {
        let bodyScope = loopBodyScope(cond, source, scope);
        emit(map, ts.startByte(body), bodyScope);
        walkNode(body, source, uri, bodyScope, map);
    }
}

// The node types walked other than by their children, by type: a table, as
// most nodes reached are none of these.
const WALKERS = {
    // Standalone block: new scope layer for its own declarations.
    statement_block: (node, source, uri, scope, map) => walkBlock(node, source, uri, makeScope(scope), map),
    // An alt-syntax body reached without its statement (normally the
    // statement's walker threads it): like a block.
    statement_list: (node, source, uri, scope, map) => walkStatementList(node, source, uri, makeScope(scope), map),
    if_statement: walkIfStmt,
    for_in_statement: walkForIn,
    for_statement: walkForStmt,
    for_in_alt_statement: walkForInAlt,
    for_alt_statement: walkForAlt,
    while_alt_statement: walkWhileAlt,
    if_alt_statement: walkIfAlt,
    while_statement: walkWhile,
    try_statement: walkTry,
    switch_statement: walkSwitch,
    function_declaration: walkFn,
    function_expression: walkFn,
    arrow_function: walkFn,
    ternary_expression: walkTernary,
    binary_expression: walkBinary,
};

walkNode = function(node, source, uri, scope, map) {
    let w = WALKERS[ts.nodeType(node)];
    if (w) return w(node, source, uri, scope, map);
    for (let c in ts.namedChildren(node))
        if (holdsMark(ts.startByte(c), ts.endByte(c)))
            walkNode(c, source, uri, scope, map);
};

// Walk the file's statements into map, with the module state set up for it.
function walkFile(uri, source, root, map) {
    _marks = ts.descendantOffsets(root, SCOPE_TYPES);
    _pos = 0;
    _chainRoots = {};
    collectBindings(root, source);
    setReturnScopes({ uri, at: (offset, from) => {
        let c = checkpointAt(map, offset);
        return (c && c.offset >= from) ? c.scope : null;
    } });
    let scope = importScope(uri);
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
}

// Build a sorted [(offset, scope)] map for the whole file.
// Checkpoints are emitted before each statement, so scopeAtOffset(map, X)
// returns the scope with all declarations from statements that begin before X.
// A map built while another is (a return type inferred meanwhile) gets the
// module state to itself, and gives it back even when the walk throws.
export function buildScopeMap(uri, source, tree) {
    let map = [];
    let outer = [_marks, _pos, _assigns, _decls, _captured, _capturedType, _chainRoots,
        setReturnScopes(null)];
    function restore() {
        _marks = outer[0];
        _pos = outer[1];
        _assigns = outer[2];
        _decls = outer[3];
        _captured = outer[4];
        _capturedType = outer[5];
        _chainRoots = outer[6];
        setReturnScopes(outer[7]);
    }
    try {
        walkFile(uri, source, ts.rootNode(tree), map);
    } catch (e) {
        restore();
        die(e);
    }
    restore();
    return map;
};
