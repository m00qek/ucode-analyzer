import * as ts from 'tree_sitter';
import * as dag from 'code_analysis.dag.dag';
import { parseDoc } from 'code_analysis.types.doc_parser';
import { unify, substitute } from 'code_analysis.types.unifier';
import { memoGet, memoSet, docMapGet, docMapSet, lineTableFor } from 'code_analysis.memo';
import { makeScope, scopeGet, scopeSet } from 'code_analysis.types.scope';
import { parseGuard, applyGuard } from 'code_analysis.types.narrowing';
import { UNKNOWN, BOOL, STR, INT, FLOAT, NULL_T, unionOf, memberOfType, literal } from 'code_analysis.types.type_utils';
import { offsetToPosition, docBeforeMap, docBearingStatement } from 'code_analysis.positions';
import { stringLiteralText, firstNamed } from 'code_analysis.ast_text';
import { exportType, dagNamedLookup, dagMemberLookup } from 'code_analysis.types.dag_bridge';

// ── Preceding JSDoc ────────────────────────────────────────────────────────

// Walk up to the nearest enclosing program or statement_block, then return
// the /** */ immediately before the containing statement. The parent's whole
// child list is scanned once (docBeforeMap) and cached per (uri, parent) so a
// file with many sibling functions doesn't rescan the list per function.
function precedingDoc(node, source, uri) {
	let s = docBearingStatement(node);
	if (!s.parent) return null;

	let pKey = ts.startByte(s.parent) + '|' + ts.endByte(s.parent);
	let map = docMapGet(uri, pKey);
	if (!map) {
		map = docBeforeMap(s.parent, source);
		docMapSet(uri, pKey, map);
	}
	return map[ts.startByte(s.target)] ?? null;
}

// ── Forward declarations (mutual recursion) ────────────────────────────────

let _infer;
let _collectReturns;

// ── Internal helpers ───────────────────────────────────────────────────────

// When fn is a callback argument in a call_expression, return the expected
// function type for that parameter position with type variables resolved from
// preceding arguments.  Returns null when the context cannot be determined.
function callbackExpectedType(fn, source, uri, scope, depth) {
	let argsNode = ts.parent(fn);
	if (!argsNode || ts.nodeType(argsNode) !== 'arguments') return null;
	let callNode = ts.parent(argsNode);
	if (!callNode || ts.nodeType(callNode) !== 'call_expression') return null;

	let callee = ts.childByField(callNode, 'function');
	if (!callee) return null;
	let calleeType = _infer(callee, source, uri, scope, depth + 1);
	if (!calleeType || calleeType.kind !== 'function') return null;

	let args = ts.namedChildren(argsNode);
	let fnStart = ts.startByte(fn);
	let fnIdx = -1;
	for (let i = 0; i < length(args); i++) {
		if (ts.startByte(args[i]) === fnStart) { fnIdx = i; break; }
	}
	if (fnIdx < 0 || fnIdx >= length(calleeType.params)) return null;

	let bindings = {};
	for (let i = 0; i < fnIdx; i++) {
		if (i >= length(calleeType.params)) break;
		let argType = _infer(args[i], source, uri, scope, depth + 1);
		unify(calleeType.params[i].type ?? UNKNOWN, argType, bindings, 0);
	}

	let expectedType = substitute(calleeType.params[fnIdx].type ?? UNKNOWN, bindings);
	return (expectedType && expectedType.kind === 'function') ? expectedType : null;
}

// The `@type` a /** */ before a let/const declares for its variables, or null.
export function declaredType(stmt, source, uri) {
	let docTxt = precedingDoc(stmt, source, uri);
	return docTxt ? parseDoc(docTxt).type : null;
};

export function processDecl(stmt, source, uri, scope, depth) {
	let declared = declaredType(stmt, source, uri);
	for (let i = 0; i < ts.namedChildCount(stmt); i++) {
		let decl = ts.namedChild(stmt, i);
		if (ts.nodeType(decl) !== 'variable_declarator') continue;
		let nameNode = ts.childByField(decl, 'name');
		let valNode  = ts.childByField(decl, 'value');
		if (nameNode && ts.nodeType(nameNode) === 'identifier') {
			let t = declared ?? (valNode ? _infer(valNode, source, uri, scope, depth + 1) : UNKNOWN);
			scopeSet(scope, ts.text(nameNode, source), t);
		}
	}
};

// Collect types of all return expressions within node, recursing into control
// flow but not crossing nested function boundaries.  Tracks let declarations
// encountered along the way so returns inside if-bodies can resolve local vars.
_collectReturns = function(node, source, uri, scope, depth, out) {
	let n = ts.namedChildCount(node);
	for (let i = 0; i < n; i++) {
		let child = ts.namedChild(node, i);
		let ct = ts.nodeType(child);
		if (ct === 'return_statement') {
			let expr = firstNamed(child);
			push(out, expr ? _infer(expr, source, uri, scope, depth + 1) : NULL_T);
		} else if (ct === 'lexical_declaration') {
			processDecl(child, source, uri, scope, depth);
		} else if (ct !== 'function_declaration' && ct !== 'arrow_function' && ct !== 'function_expression') {
			_collectReturns(child, source, uri, scope, depth, out);
		}
	}
};

// Infer the type of an arrow_function or function_expression node.
//
// Parameter types are resolved in priority order:
//   1. expectedType, when explicitly provided (e.g. when the caller already
//      knows the declared signature from JSDoc @returns).
//   2. callbackExpectedType — derives expected params from the call site when
//      this function is passed as an argument.
//   3. UNKNOWN — used for any param not covered by the above.
//
// The return type is always inferred from the body; expectedType.return is
// never used (only the caller that has a @returns declaration short-circuits
// before calling inferArrow).
function inferArrow(node, source, uri, scope, depth, expectedType) {
	if (!expectedType)
		expectedType = callbackExpectedType(node, source, uri, scope, depth);

	let expectedParams = (expectedType && expectedType.kind === 'function')
		? expectedType.params : [];

	let params = [];
	// Use field access so named function_expression (first named child is the
	// function name, not formal_parameters) binds params correctly.
	let formalParams = ts.childByField(node, 'parameters');
	if (formalParams) {
		for (let i = 0; i < ts.namedChildCount(formalParams); i++) {
			let pnode = ts.namedChild(formalParams, i);
			if (ts.nodeType(pnode) === 'rest_element') {
				let inner = firstNamed(pnode);
				if (inner && ts.nodeType(inner) === 'identifier')
					push(params, { name: ts.text(inner, source), type: { kind: 'generic', base: 'list', params: [UNKNOWN] } });
				continue;
			}
			if (ts.nodeType(pnode) !== 'identifier') continue;
			let ptype = (i < length(expectedParams))
				? (expectedParams[i].type ?? UNKNOWN) : UNKNOWN;
			push(params, { name: ts.text(pnode, source), type: ptype });
		}
	} else {
		// Single-param arrow `x => ...` — bare identifier in `parameter` field.
		let param = ts.childByField(node, 'parameter');
		if (param && ts.nodeType(param) === 'identifier') {
			let ptype = length(expectedParams) > 0
				? (expectedParams[0].type ?? UNKNOWN) : UNKNOWN;
			push(params, { name: ts.text(param, source), type: ptype });
		}
	}

	let childScope = makeScope(scope);
	for (let i = 0; i < length(params); i++)
		scopeSet(childScope, params[i].name, params[i].type);

	let bodyNode = ts.childByField(node, 'body');
	let ret = UNKNOWN;
	if (bodyNode) {
		let bt = ts.nodeType(bodyNode);
		if (bt === 'statement_block' || bt === 'statement_list') {
			let rets = [];
			_collectReturns(bodyNode, source, uri, childScope, depth, rets);
			ret = unionOf(rets);
		} else {
			ret = _infer(bodyNode, source, uri, childScope, depth + 1);
		}
	}
	return { kind: 'function', params, return: ret };
}

// True if `name` is bound in a non-root scope — a genuine local shadow, as
// opposed to a builtin sitting in the root scope (parent === null). The builtin
// scope is the only scope with a null parent, so we stop before it.
function locallyShadowed(scope, name) {
	let s = scope;
	while (s && s.parent) {
		if (exists(s.bindings, name)) return true;
		s = s.parent;
	}
	return false;
}

// require("spec") is ucode's runtime module loader — the dynamic counterpart of
// a static import. Model its result as the module named by the (literal)
// specifier so hover, completion and member typing on the returned value behave
// exactly like a namespace import (`fw4.zones()` resolves via dag.resolveMember).
// Returns null for a shadowed `require`, a non-`require` callee, or a specifier
// that is not a plain string literal (nothing to resolve statically).
function requireModuleType(node, source, scope) {
	let fnNode = ts.childByField(node, 'function');
	if (!fnNode || ts.nodeType(fnNode) !== 'identifier') return null;
	if (ts.text(fnNode, source) !== 'require') return null;
	if (locallyShadowed(scope, 'require')) return null;   // a user binding is not the builtin

	let argsNode = ts.childByField(node, 'arguments');
	let args = argsNode ? ts.namedChildren(argsNode) : [];
	if (length(args) < 1 || ts.nodeType(args[0]) !== 'string') return null;

	let path = stringLiteralText(args[0], source);
	return length(path) ? { kind: 'module', path } : null;   // "" → nothing to resolve
}

function inferCall(node, source, uri, scope, depth) {
	let mod = requireModuleType(node, source, scope);
	if (mod) return mod;

	let fnNode   = ts.childByField(node, 'function');
	let argsNode = ts.childByField(node, 'arguments');
	if (!fnNode) return UNKNOWN;

	let fnType = _infer(fnNode, source, uri, scope, depth + 1);
	if (!fnType || fnType.kind !== 'function') return UNKNOWN;

	let args = argsNode ? ts.namedChildren(argsNode) : [];
	let bindings = {};
	for (let i = 0; i < length(args); i++) {
		let arg = args[i];
		let paramType = (i < length(fnType.params))
			? (fnType.params[i].type ?? UNKNOWN) : UNKNOWN;
		let argType = _infer(arg, source, uri, scope, depth + 1);
		unify(paramType, argType, bindings, 0);
	}
	return substitute(fnType.return, bindings);
}

function inferMember(node, source, uri, scope, depth) {
	let objNode  = ts.childByField(node, 'object');
	let propNode = ts.childByField(node, 'property');
	if (!objNode || !propNode) return UNKNOWN;
	let propName = ts.text(propNode, source);
	let result = UNKNOWN;

	// Resolve the object through the local scope first — matching inferIdentifier's
	// precedence so a local binding shadows a same-named namespace import
	// (`let cfg = {…}` wins over `import * as cfg`). A namespace alias that isn't
	// shadowed is itself in scope as a module type and resolves here too.
	let objType = _infer(objNode, source, uri, scope, (depth ?? 0) + 1);
	if (objType && objType.kind === 'module') {
		let r = dag.resolveMember(objType.path, propName);
		if (r) result = exportType(r.exp, r.uri);
	} else if (objType && objType.kind !== 'unknown') {
		result = memberOfType(objType, propName);
	}

	// Fall back to the DAG namespace lookup only when the scope couldn't type the
	// object — e.g. a bare alias identifier absent from the scope map.
	if (result.kind === 'unknown' && ts.nodeType(objNode) === 'identifier') {
		let dagResult = dagMemberLookup(uri, ts.text(objNode, source), propName);
		if (dagResult) result = dagResult;
	}
	if (ts.childByField(node, 'optional_chain'))
		return { kind: 'nullable', inner: result };
	return result;
}

// Infer arr[i] (list element) or obj["key"] (record field).
// The optional_chain field on the node indicates `?.[]` syntax, wrapping in nullable.
function inferSubscript(node, source, uri, scope, depth) {
	let objNode = ts.childByField(node, 'object');
	let idxNode = ts.childByField(node, 'index');
	if (!objNode) return UNKNOWN;

	let objType = _infer(objNode, source, uri, scope, depth + 1);
	// Unwrap nullable for the lookup, re-wrap at the end if optional chain.
	let baseType = (objType && objType.kind === 'nullable') ? objType.inner : objType;

	let elem = UNKNOWN;
	if (baseType && baseType.kind === 'generic' && baseType.base === 'list') {
		elem = baseType.params[0] ?? UNKNOWN;
	} else if (baseType && baseType.kind === 'record' && idxNode &&
	           ts.nodeType(idxNode) === 'string') {
		elem = memberOfType(baseType, stringLiteralText(idxNode, source));
	}

	return ts.childByField(node, 'optional_chain')
		? { kind: 'nullable', inner: elem }
		: elem;
}

// Infer the type contributed by a spread element inside an array or object.
// In array context: ...list<T> → T (the element type is what gets spread into the array).
// In object context: caller handles field merging; here return the spread type itself.
function inferSpread(node, source, uri, scope, depth) {
	let inner = firstNamed(node);
	if (!inner) return UNKNOWN;
	let t = _infer(inner, source, uri, scope, depth + 1);
	if (t && t.kind === 'generic' && t.base === 'list')
		return t.params[0] ?? UNKNOWN;
	return t;
}

// ── Node-type handlers ─────────────────────────────────────────────────────

function inferNumber(node, source) {
	let text = ts.text(node, source);
	// Hex / binary / octal literals are always integers, even though hex digits
	// include 'e'/'E' (0x1e is int). Only a decimal literal with a fraction (.)
	// or an exponent (e/E) is a float — e.g. 1e5 and 5.0 are doubles, 0x1e is not.
	if (!match(text, /^0[xXbBoO]/) && match(text, /[.eE]/))
		return { kind: 'primitive', name: 'float' };
	return INT;
}

function inferIdentifier(node, source, uri, scope) {
	let name = ts.text(node, source);
	return scopeGet(scope, name) ?? dagNamedLookup(uri, name) ?? UNKNOWN;
}

// Cursor on a property name in obj.prop — infer the whole member expression.
function inferPropertyIdentifier(node, source, uri, scope, depth) {
	let parent = ts.parent(node);
	if (parent && ts.nodeType(parent) === 'member_expression')
		return inferMember(parent, source, uri, scope, depth);
	return UNKNOWN;
}

function inferParenthesized(node, source, uri, scope, depth) {
	let inner = firstNamed(node);
	return inner ? _infer(inner, source, uri, scope, depth + 1) : UNKNOWN;
}

function inferUnary(node, source, uri, scope, depth) {
	let op = ts.nodeType(ts.childByField(node, 'operator'));
	if (op === '!') return BOOL;   // `delete` is now its own delete_expression node
	if (op === '~') return INT;   // bitwise complement is always int
	let operand = ts.childByField(node, 'argument');
	let t = operand ? _infer(operand, source, uri, scope, depth + 1) : UNKNOWN;
	// Unary +/- coerce to a number: float when the operand is float, int when it
	// is int; for a string/unknown operand it's numeric but int-vs-float is
	// undetermined (+"5" is int, +"5.0" is float), so don't claim the operand's
	// own type (a string result would be wrong).
	if (op === '+' || op === '-') {
		if (t.kind === 'primitive' && t.name === 'float') return FLOAT;
		if (t.kind === 'primitive' && t.name === 'int')   return INT;
		return UNKNOWN;
	}
	return t;
}

function inferBinary(node, source, uri, scope, depth) {
	let op = ts.nodeType(ts.childByField(node, 'operator'));
	if (op === '<'  || op === '>'  || op === '<=' || op === '>=' ||
	    op === '==' || op === '!=' || op === '===' || op === '!==')
		return BOOL;
	let left  = ts.childByField(node, 'left');
	let right = ts.childByField(node, 'right');
	if (op === '&&' || op === '||') {
		let lt = left  ? _infer(left,  source, uri, scope, depth + 1) : UNKNOWN;
		let rt = right ? _infer(right, source, uri, scope, depth + 1) : UNKNOWN;
		return unionOf([lt, rt]);
	}
	if (op === '??') {
		// a ?? b evaluates to a when non-null, else b. Strip null/nullable from
		// the left and union with the right.
		let lt = left  ? _infer(left,  source, uri, scope, depth + 1) : UNKNOWN;
		let rt = right ? _infer(right, source, uri, scope, depth + 1) : UNKNOWN;
		let nonNullLeft = (lt.kind === 'nullable') ? lt.inner :
		                  (lt.kind === 'primitive' && lt.name === 'null') ? null : lt;
		return nonNullLeft ? unionOf([nonNullLeft, rt]) : rt;
	}
	if (op === '+') {
		let lt = left  ? _infer(left,  source, uri, scope, depth + 1) : UNKNOWN;
		let rt = right ? _infer(right, source, uri, scope, depth + 1) : UNKNOWN;
		if ((lt.kind === 'primitive' && lt.name === 'string') ||
		    (rt.kind === 'primitive' && rt.name === 'string'))
			return STR;
	}
	let lt = left  ? _infer(left,  source, uri, scope, depth + 1) : INT;
	let rt = right ? _infer(right, source, uri, scope, depth + 1) : INT;
	if ((lt.kind === 'primitive' && lt.name === 'float') ||
	    (rt.kind === 'primitive' && rt.name === 'float'))
		return FLOAT;
	return lt;
}

function inferTernary(node, source, uri, scope, depth) {
	let cond = ts.childByField(node, 'condition');
	let a    = ts.childByField(node, 'consequence');
	let b    = ts.childByField(node, 'alternative');
	let guard = parseGuard(cond, source);
	let trueScope  = makeScope(scope);
	let falseScope = makeScope(scope);
	applyGuard(trueScope,  guard, true);
	applyGuard(falseScope, guard, false);
	let ta = a ? _infer(a, source, uri, trueScope,  depth + 1) : UNKNOWN;
	let tb = b ? _infer(b, source, uri, falseScope, depth + 1) : UNKNOWN;
	if (ta.kind === tb.kind && ta.kind === 'primitive' && ta.name === tb.name)
		return ta;
	return { kind: 'union', members: [ta, tb] };
}

function inferArray(node, source, uri, scope, depth) {
	let n = ts.namedChildCount(node);
	if (n === 0) return { kind: 'generic', base: 'list', params: [UNKNOWN] };
	let members = [];
	for (let i = 0; i < n; i++) {
		let t = _infer(ts.namedChild(node, i), source, uri, scope, depth + 1);
		let seen = false;
		for (let j = 0; j < length(members); j++) {
			let m = members[j];
			if (m.kind === t.kind && (m.kind !== 'primitive' || m.name === t.name)) {
				seen = true; break;
			}
		}
		if (!seen) push(members, t);
	}
	let elem = length(members) === 1 ? members[0] : { kind: 'union', members };
	return { kind: 'generic', base: 'list', params: [elem] };
}

// If valNode is a direct string/number literal, return its concrete value so the
// containing object-literal field can carry a literal type (which drives
// discriminated-union narrowing). Any other expression returns null and the field
// keeps its widened base type — literals are born only here, at field positions.
function literalValueOf(valNode, source) {
	if (!valNode) return null;
	let nt = ts.nodeType(valNode);
	if (nt === 'string')
		return stringLiteralText(valNode, source);
	if (nt === 'number') {
		let v = +ts.text(valNode, source);
		if (type(v) === 'int' || type(v) === 'double') return v;
	}
	return null;
}

function inferObject(node, source, uri, scope, depth) {
	let lineTable = lineTableFor(uri, source);
	let fields = [];
	// A record is "open" when its full field set can't be known statically —
	// spreading a non-record (e.g. an untyped value) contributes unknown extra
	// keys. Callers must not report unknown-property against an open record.
	let open = false;
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let child = ts.namedChild(node, i);
		let ct = ts.nodeType(child);
		if (ct === 'spread_element') {
			// { ...obj } — merge fields from the spread type into this record.
			let inner = firstNamed(child);
			let t = inner ? _infer(inner, source, uri, scope, depth + 1) : null;
			if (t && t.kind === 'record') {
				for (let j = 0; j < length(t.fields); j++)
					push(fields, t.fields[j]);
				if (t.open) open = true;   // openness propagates through spreads
			} else {
				open = true;               // spread of a non-record: keys unknowable
			}
			continue;
		}
		if (ct === 'shorthand_property_identifier') {
			// { x } — key and value are both the identifier x
			let name = ts.text(child, source);
			let position = offsetToPosition(source, lineTable, ts.startByte(child));
			push(fields, { name, type: scopeGet(scope, name) ?? UNKNOWN, position });
			continue;
		}
		if (ct !== 'pair') continue;
		let keyNode = ts.childByField(child, 'key');
		let valNode = ts.childByField(child, 'value');
		if (!keyNode) continue;
		let kt = ts.nodeType(keyNode);
		let keyName = null;
		if (kt === 'property_identifier' || kt === 'identifier') {
			keyName = ts.text(keyNode, source);
		} else if (kt === 'string') {
			let s = stringLiteralText(keyNode, source);
			keyName = length(s) ? s : null;
		}
		if (!keyName) continue;
		let position = offsetToPosition(source, lineTable, ts.startByte(keyNode));
		let ft = valNode ? _infer(valNode, source, uri, scope, depth + 1) : UNKNOWN;
		if (ft.kind === 'primitive') {
			let lv = literalValueOf(valNode, source);
			if (lv !== null) ft = literal(ft.name, lv);
		}
		push(fields, { name: keyName, type: ft, position });
	}
	let result = { kind: 'record', fields, sourceUri: uri };
	if (open) result.open = true;
	return result;
}

function inferFunctionExpr(node, source, uri, scope, depth) {
	let docTxt = precedingDoc(node, source, uri);
	let doc = docTxt ? parseDoc(docTxt) : null;
	// @returns declared: trust it and skip body inference.
	if (doc && doc.returns && doc.returns.type) {
		return {
			kind: 'function',
			params: map(doc.params, (p) => ({ name: p.name, type: p.type ?? UNKNOWN })),
			return: doc.returns.type,
		};
	}
	// @param annotations present: use them as the expected type so they take
	// priority over callbackExpectedType (which would otherwise override JSDoc).
	let expected = (doc && length(doc.params) > 0)
		? { kind: 'function', params: map(doc.params, (p) => ({ name: p.name, type: p.type ?? UNKNOWN })), return: UNKNOWN }
		: null;
	return inferArrow(node, source, uri, scope, depth, expected);
}

function inferReturnStatement(node, source, uri, scope, depth) {
	let expr = firstNamed(node);
	return expr ? _infer(expr, source, uri, scope, depth + 1) : NULL_T;
}

function inferLexicalDecl(node, source, uri, scope, depth) {
	processDecl(node, source, uri, scope, depth);
	return UNKNOWN;
}

function inferFunctionDecl(node, source, uri, scope, depth) {
	let docTxt = precedingDoc(node, source, uri);
	let doc = docTxt ? parseDoc(docTxt) : null;
	let docParams = (doc && doc.params) ? doc.params : [];

	// Params: from JSDoc @param when annotated, otherwise one UNKNOWN entry per
	// formal parameter so addParamScope can still bind the names.
	let params = [];
	if (length(docParams) > 0) {
		params = map(docParams, (p) => ({ name: p.name, type: p.type ?? UNKNOWN }));
	} else {
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let child = ts.namedChild(node, i);
			if (ts.nodeType(child) !== 'formal_parameters') continue;
			for (let j = 0; j < ts.namedChildCount(child); j++) {
				let p = ts.namedChild(child, j);
				if (ts.nodeType(p) === 'rest_element') {
					let inner = firstNamed(p);
					if (inner && ts.nodeType(inner) === 'identifier')
						push(params, { name: ts.text(inner, source), type: { kind: 'generic', base: 'list', params: [UNKNOWN] } });
					continue;
				}
				if (ts.nodeType(p) !== 'identifier') continue;
				push(params, { name: ts.text(p, source), type: UNKNOWN });
			}
			break;
		}
	}

	// Return type: declared via @returns, or infer from all return statements.
	let ret = (doc && doc.returns && doc.returns.type) ? doc.returns.type : UNKNOWN;
	if (ret === UNKNOWN) {
		let body = ts.childByField(node, 'body');
		if (body) {
			let bodyScope = makeScope(scope);
			for (let i = 0; i < length(params); i++)
				scopeSet(bodyScope, params[i].name, params[i].type ?? UNKNOWN);
			let rets = [];
			_collectReturns(body, source, uri, bodyScope, depth, rets);
			ret = unionOf(rets);
		}
	}
	return { kind: 'function', params, return: ret };
}

// ── Dispatch table ─────────────────────────────────────────────────────────

let INFER = {
	'number':                   inferNumber,
	'string':                   () => STR,
	'template_string':          () => STR,
	'true':                     () => BOOL,
	'false':                    () => BOOL,
	'null':                     () => NULL_T,
	'identifier':               inferIdentifier,
	'property_identifier':      inferPropertyIdentifier,
	'parenthesized_expression': inferParenthesized,
	'unary_expression':         inferUnary,
	'delete_expression':        () => BOOL,   // `delete o.k` returns a boolean
	'binary_expression':        inferBinary,
	'ternary_expression':       inferTernary,
	'array':                    inferArray,
	'object':                   inferObject,
	'call_expression':          inferCall,
	'member_expression':        inferMember,
	'subscript_expression':     inferSubscript,
	'spread_element':           inferSpread,
	'arrow_function':           (node, source, uri, scope, depth) => inferArrow(node, source, uri, scope, depth, null),
	'function_expression':      inferFunctionExpr,
	'return_statement':         inferReturnStatement,
	'lexical_declaration':      inferLexicalDecl,
	'function_declaration':     inferFunctionDecl,
};

// ── Public API ────────────────────────────────────────────────────────────

_infer = function(node, source, uri, scope, depth) {
	if (!node || depth > 10) return UNKNOWN;
	let ntype = ts.nodeType(node);
	let offset = ts.startByte(node);
	let sid = scope ? scope.id : 0;
	let cached = memoGet(uri, offset, ntype, sid, depth);
	if (cached) return cached;
	let h = INFER[ntype];
	let type = h ? h(node, source, uri, scope, depth) : UNKNOWN;
	memoSet(uri, offset, ntype, sid, type, depth);
	return type;
};

export function inferNode(node, source, uri, scope, depth) {
	return _infer(node, source, uri, scope, depth ?? 0);
};
