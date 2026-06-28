import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag.dag';
import { parseDoc } from 'ucode_language_server.types.doc_parser';
import { unify, substitute } from 'ucode_language_server.types.unifier';
import { memoGet, memoSet } from 'ucode_language_server.memo';
import { makeScope, scopeGet, scopeSet } from 'ucode_language_server.types.scope';
import { UNKNOWN, BOOL, STR, INT, NULL_T, unionOf, memberOfType } from 'ucode_language_server.types.type_utils';

let _builtinScope = makeScope(null);
let _stdlibUri    = null;

// ── Preceding JSDoc ────────────────────────────────────────────────────────

// Return the text of the /** */ comment immediately before the nearest
// statement containing node (stopping at program or statement_block).
// Any intervening named node or // comment resets.
function precedingDoc(node, source) {
	let target = node;
	let p = ts.parent(target);
	while (p) {
		let pt = ts.nodeType(p);
		if (pt === 'program' || pt === 'statement_block') break;
		target = p;
		p = ts.parent(target);
	}
	if (!p) return null;

	let targetStart = ts.startByte(target);
	let found = null;
	let children = ts.children(p);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.startByte(c) >= targetStart) break;
		if (ts.nodeType(c) === 'comment') {
			let txt = ts.text(c, source);
			found = (substr(txt, 0, 3) === '/**') ? txt : null;
		} else if (ts.isNamed(c)) {
			found = null;
		}
	}
	return found;
}

// ── DAG helpers ────────────────────────────────────────────────────────────

function exportType(exp) {
	if (exp._moduleSpecifier) return { kind: 'module', path: exp._moduleSpecifier };
	if (exp.kind === 'function') {
		if (!exp.doc) return UNKNOWN;
		return {
			kind: 'function',
			params: map(filter(exp.doc.params, (p) => !match(p.name, /\./)), (p) => ({ name: p.name, type: p.type ?? UNKNOWN })),
			return: (exp.doc.returns ? exp.doc.returns.type : null) ?? UNKNOWN,
		};
	}
	if (exp.properties) {
		let fields = [];
		for (let i = 0; i < length(exp.properties); i++) {
			let prop = exp.properties[i];
			push(fields, { name: prop.name, type: exportType(prop), doc: prop.doc });
		}
		return { kind: 'record', fields };
	}
	if (!exp.doc) return UNKNOWN;
	return (exp.doc.returns ? exp.doc.returns.type : null) ?? UNKNOWN;
}

// Look up a symbol imported by name into uri (import { foo } from 'mod').
function dagNamedLookup(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let exp = dag.resolveExport(imp.resolvedUri, remoteName);
		if (exp) return exportType(exp);
	}
	return null;
}

// Look up a member of a namespace-imported alias (import * as mod from 'x').
function dagMemberLookup(uri, alias, member) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias !== alias || !imp.resolvedUri) continue;
		let exp = dag.resolveExport(imp.resolvedUri, member);
		return exp ? exportType(exp) : null;
	}
	return null;
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

export function processDecl(stmt, source, uri, scope, depth) {
	for (let i = 0; i < ts.namedChildCount(stmt); i++) {
		let decl = ts.namedChild(stmt, i);
		if (ts.nodeType(decl) !== 'variable_declarator') continue;
		let nameNode = ts.childByField(decl, 'name');
		let valNode  = ts.childByField(decl, 'value');
		if (nameNode && ts.nodeType(nameNode) === 'identifier') {
			let t = valNode ? _infer(valNode, source, uri, scope, depth + 1) : UNKNOWN;
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
			let expr = ts.namedChild(child, 0);
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
	let first = ts.namedChild(node, 0);
	if (first && ts.nodeType(first) === 'formal_parameters') {
		for (let i = 0; i < ts.namedChildCount(first); i++) {
			let pnode = ts.namedChild(first, i);
			if (ts.nodeType(pnode) !== 'identifier') continue;
			let ptype = (i < length(expectedParams))
				? (expectedParams[i].type ?? UNKNOWN) : UNKNOWN;
			push(params, { name: ts.text(pnode, source), type: ptype });
		}
	} else if (first && ts.nodeType(first) === 'identifier') {
		// Single-param arrow `x => ...` — bare identifier, no formal_parameters node.
		let ptype = length(expectedParams) > 0
			? (expectedParams[0].type ?? UNKNOWN) : UNKNOWN;
		push(params, { name: ts.text(first, source), type: ptype });
	}

	let childScope = makeScope(scope);
	for (let i = 0; i < length(params); i++)
		scopeSet(childScope, params[i].name, params[i].type);

	let bodyNode = ts.childByField(node, 'body');
	let ret = UNKNOWN;
	if (bodyNode) {
		if (ts.nodeType(bodyNode) === 'statement_block') {
			let rets = [];
			_collectReturns(bodyNode, source, uri, childScope, depth, rets);
			ret = unionOf(rets);
		} else {
			ret = _infer(bodyNode, source, uri, childScope, depth + 1);
		}
	}
	return { kind: 'function', params, return: ret };
}

function inferCall(node, source, uri, scope, depth) {
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
	let objNode  = ts.namedChild(node, 0);
	let propNode = ts.namedChild(node, 1);
	if (!objNode || !propNode) return UNKNOWN;
	let propName = ts.text(propNode, source);
	// Namespace import lookup only applies when the object is a direct identifier alias.
	if (ts.nodeType(objNode) === 'identifier') {
		let dagResult = dagMemberLookup(uri, ts.text(objNode, source), propName);
		if (dagResult) return dagResult;
	}
	let objType = _infer(objNode, source, uri, scope, (depth ?? 0) + 1);
	if (objType && objType.kind === 'module') {
		let r = dag.resolveMember(objType.path, propName);
		if (r) return exportType(r.exp);
	}
	if (objType && objType.kind !== 'unknown')
		return memberOfType(objType, propName);
	return UNKNOWN;
}

// ── Node-type handlers ─────────────────────────────────────────────────────

function inferNumber(node, source) {
	return match(ts.text(node, source), /\./)
		? { kind: 'primitive', name: 'float' } : INT;
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
	let inner = ts.namedChild(node, 0);
	return inner ? _infer(inner, source, uri, scope, depth + 1) : UNKNOWN;
}

function inferUnary(node, source, uri, scope, depth) {
	let op = ts.nodeType(ts.child(node, 0));
	if (op === '!') return BOOL;
	let operand = ts.namedChild(node, 0);
	return operand ? _infer(operand, source, uri, scope, depth + 1) : UNKNOWN;
}

function inferBinary(node, source, uri, scope, depth) {
	let op = ts.nodeType(ts.child(node, 1));
	if (op === '<'  || op === '>'  || op === '<=' || op === '>=' ||
	    op === '==' || op === '!=' || op === '&&' || op === '||')
		return BOOL;
	let left  = ts.namedChild(node, 0);
	let right = ts.namedChild(node, 1);
	if (op === '+') {
		let lt = left  ? _infer(left,  source, uri, scope, depth + 1) : UNKNOWN;
		let rt = right ? _infer(right, source, uri, scope, depth + 1) : UNKNOWN;
		if ((lt.kind === 'primitive' && lt.name === 'string') ||
		    (rt.kind === 'primitive' && rt.name === 'string'))
			return STR;
	}
	return left ? _infer(left, source, uri, scope, depth + 1) : INT;
}

function inferTernary(node, source, uri, scope, depth) {
	let a = ts.namedChild(node, 1);
	let b = ts.namedChild(node, 2);
	let ta = a ? _infer(a, source, uri, scope, depth + 1) : UNKNOWN;
	let tb = b ? _infer(b, source, uri, scope, depth + 1) : UNKNOWN;
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

function inferObject(node, source, uri, scope, depth) {
	let fields = [];
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let pair = ts.namedChild(node, i);
		if (ts.nodeType(pair) !== 'pair') continue;
		let keyNode = ts.childByField(pair, 'key');
		let valNode = ts.childByField(pair, 'value');
		if (!keyNode) continue;
		let kt = ts.nodeType(keyNode);
		let keyName = (kt === 'property_identifier' || kt === 'identifier')
			? ts.text(keyNode, source) : null;
		if (!keyName) continue;
		push(fields, { name: keyName, type: valNode ? _infer(valNode, source, uri, scope, depth + 1) : UNKNOWN });
	}
	return { kind: 'record', fields };
}

function inferFunctionExpr(node, source, uri, scope, depth) {
	let docTxt = precedingDoc(node, source);
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
	let expr = ts.namedChild(node, 0);
	return expr ? _infer(expr, source, uri, scope, depth + 1) : NULL_T;
}

function inferLexicalDecl(node, source, uri, scope, depth) {
	processDecl(node, source, uri, scope, depth);
	return UNKNOWN;
}

function inferFunctionDecl(node, source, uri, scope, depth) {
	let docTxt = precedingDoc(node, source);
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
	'binary_expression':        inferBinary,
	'ternary_expression':       inferTernary,
	'array':                    inferArray,
	'object':                   inferObject,
	'call_expression':          inferCall,
	'member_expression':        inferMember,
	'arrow_function':           (node, source, uri, scope, depth) => inferArrow(node, source, uri, scope, depth, null),
	'function_expression':      inferFunctionExpr,
	'return_statement':         inferReturnStatement,
	'lexical_declaration':      inferLexicalDecl,
	'function_declaration':     inferFunctionDecl,
};

// ── Scope building ─────────────────────────────────────────────────────────

export function importScope(uri) {
	let scope = makeScope(_builtinScope);
	let imps = dag.importsOf(uri);
	if (!imps) return scope;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias) {
			// Namespace import: import * as alias from 'mod'
			if (imp.resolvedUri)
				scopeSet(scope, imp.alias, { kind: 'module', path: imp.specifier });
			continue;
		}
		if (!imp.resolvedUri) continue;
		for (let j = 0; j < length(imp.symbols); j++) {
			let localName = imp.symbols[j];
			let remoteName = (imp.renames && imp.renames[localName]) ?? localName;
			let r = dag.resolveExport(imp.resolvedUri, remoteName);
			if (r) scopeSet(scope, localName, exportType(r));
		}
	}
	return scope;
};

// ── Public API ────────────────────────────────────────────────────────────

_infer = function(node, source, uri, scope, depth) {
	if (!node || depth > 10) return UNKNOWN;
	let ntype = ts.nodeType(node);
	let offset = ts.startByte(node);
	let cached = memoGet(uri, offset, ntype);
	if (cached) return cached;
	let h = INFER[ntype];
	let type = h ? h(node, source, uri, scope, depth) : UNKNOWN;
	memoSet(uri, offset, ntype, type);
	return type;
};

export function inferNode(node, source, uri, scope, depth) {
	return _infer(node, source, uri, scope, depth ?? 0);
};

export function stdlibUri() { return _stdlibUri; };

export function initBuiltinsFromDag(uri) {
	let exps = dag.exportsOf(uri);
	if (!exps || length(exps) === 0) return;
	_stdlibUri = uri;
	let s = makeScope(null);
	for (let i = 0; i < length(exps); i++)
		scopeSet(s, exps[i].name, exportType(exps[i]));
	_builtinScope = s;
};
