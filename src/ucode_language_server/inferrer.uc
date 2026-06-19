import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag';
import { parseDoc } from 'ucode_language_server.doc_parser';
import { unify, substitute } from 'ucode_language_server.type_unifier';
import { memoGet, memoSet } from 'ucode_language_server.memo';
import { makeScope, scopeGet, scopeSet } from 'ucode_language_server.scope';

let UNKNOWN = { kind: 'unknown' };
let BOOL    = { kind: 'primitive', name: 'boolean' };
let STR     = { kind: 'primitive', name: 'string' };
let INT     = { kind: 'primitive', name: 'int' };
let NULL_T  = { kind: 'primitive', name: 'null' };

// ── Preceding JSDoc ────────────────────────────────────────────────────────

// Return the text of the /** */ comment immediately before the top-level
// statement containing node. Any intervening named node or // comment resets.
function precedingDoc(node, source) {
	let target = node;
	let p = ts.parent(target);
	while (p && ts.nodeType(p) !== 'program') {
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
	if (!exp.doc) return UNKNOWN;
	let doc = exp.doc;
	if (exp.kind === 'function') {
		return {
			kind: 'function',
			params: map(doc.params, (p) => ({ name: p.name, type: p.type ?? UNKNOWN })),
			return: (doc.returns ? doc.returns.type : null) ?? UNKNOWN,
		};
	}
	return (doc.returns ? doc.returns.type : null) ?? UNKNOWN;
}

// Look up a symbol imported by name into uri (import { foo } from 'mod').
function dagNamedLookup(uri, name) {
	let imps = dag.importsOf(uri);
	if (!imps) return null;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
		let exps = dag.exportsOf(imp.resolvedUri);
		if (!exps) continue;
		for (let j = 0; j < length(exps); j++)
			if (exps[j].name === name) return exportType(exps[j]);
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
		let exps = dag.exportsOf(imp.resolvedUri);
		if (!exps) break;
		for (let j = 0; j < length(exps); j++)
			if (exps[j].name === member) return exportType(exps[j]);
		break;
	}
	return null;
}

// ── Forward declaration (mutual recursion) ─────────────────────────────────

let _infer;

// ── Internal helpers ───────────────────────────────────────────────────────

function processDecl(stmt, source, uri, scope, depth) {
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
}

function inferArrow(node, source, uri, scope, depth, expectedType) {
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
		let ptype = length(expectedParams) > 0
			? (expectedParams[0].type ?? UNKNOWN) : UNKNOWN;
		push(params, { name: ts.text(first, source), type: ptype });
	}

	let childScope = makeScope(scope);
	for (let i = 0; i < length(params); i++)
		scopeSet(childScope, params[i].name, params[i].type);

	let bodyNode = ts.childByField(node, 'body');
	let ret = bodyNode ? _infer(bodyNode, source, uri, childScope, depth + 1) : UNKNOWN;
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

		let argType;
		if (ts.nodeType(arg) === 'arrow_function') {
			let expected = substitute(paramType, bindings);
			argType = inferArrow(arg, source, uri, scope, depth + 1, expected);
		} else {
			argType = _infer(arg, source, uri, scope, depth + 1);
		}
		unify(paramType, argType, bindings, 0);
	}
	return substitute(fnType.return, bindings);
}

function inferMember(node, source, uri) {
	let objNode  = ts.namedChild(node, 0);
	let propNode = ts.namedChild(node, 1);
	if (!objNode || !propNode || ts.nodeType(objNode) !== 'identifier') return UNKNOWN;
	return dagMemberLookup(uri, ts.text(objNode, source), ts.text(propNode, source)) ?? UNKNOWN;
}

function inferInner(node, source, uri, scope, depth) {
	let ntype = ts.nodeType(node);

	if (ntype === 'number')
		return match(ts.text(node, source), /\./)
			? { kind: 'primitive', name: 'float' } : INT;
	if (ntype === 'string' || ntype === 'template_string') return STR;
	if (ntype === 'true' || ntype === 'false') return BOOL;
	if (ntype === 'null') return NULL_T;

	if (ntype === 'identifier') {
		let name = ts.text(node, source);
		return scopeGet(scope, name) ?? dagNamedLookup(uri, name) ?? UNKNOWN;
	}

	if (ntype === 'parenthesized_expression') {
		let inner = ts.namedChild(node, 0);
		return inner ? _infer(inner, source, uri, scope, depth + 1) : UNKNOWN;
	}

	if (ntype === 'unary_expression') {
		let op = ts.nodeType(ts.child(node, 0));
		if (op === '!') return BOOL;
		let operand = ts.namedChild(node, 0);
		return operand ? _infer(operand, source, uri, scope, depth + 1) : UNKNOWN;
	}

	if (ntype === 'binary_expression') {
		let op = ts.nodeType(ts.child(node, 1));
		if (op === '<'  || op === '>'  || op === '<=' || op === '>=' ||
		    op === '==' || op === '!=' || op === '&&' || op === '||')
			return BOOL;
		let left = ts.namedChild(node, 0);
		if (op === '+' && left) {
			let lt = _infer(left, source, uri, scope, depth + 1);
			if (lt.kind === 'primitive' && lt.name === 'string') return STR;
		}
		return left ? _infer(left, source, uri, scope, depth + 1) : INT;
	}

	if (ntype === 'ternary_expression') {
		let a = ts.namedChild(node, 1);
		let b = ts.namedChild(node, 2);
		let ta = a ? _infer(a, source, uri, scope, depth + 1) : UNKNOWN;
		let tb = b ? _infer(b, source, uri, scope, depth + 1) : UNKNOWN;
		if (ta.kind === tb.kind && ta.kind === 'primitive' && ta.name === tb.name)
			return ta;
		return { kind: 'union', members: [ta, tb] };
	}

	if (ntype === 'array') {
		let elem = ts.namedChildCount(node) > 0
			? _infer(ts.namedChild(node, 0), source, uri, scope, depth + 1) : UNKNOWN;
		return { kind: 'generic', base: 'list', params: [elem] };
	}

	if (ntype === 'object') return UNKNOWN;

	if (ntype === 'call_expression')   return inferCall(node, source, uri, scope, depth);
	if (ntype === 'member_expression') return inferMember(node, source, uri);
	if (ntype === 'arrow_function')    return inferArrow(node, source, uri, scope, depth, null);

	if (ntype === 'return_statement') {
		let expr = ts.namedChild(node, 0);
		return expr ? _infer(expr, source, uri, scope, depth + 1) : NULL_T;
	}

	if (ntype === 'lexical_declaration') {
		processDecl(node, source, uri, scope, depth);
		return UNKNOWN;
	}

	if (ntype === 'function_declaration') {
		let docTxt = precedingDoc(node, source);
		if (docTxt) {
			let doc = parseDoc(docTxt);
			if (doc.returns && doc.returns.type)
				return {
					kind: 'function',
					params: map(doc.params, (p) => ({ name: p.name, type: p.type ?? UNKNOWN })),
					return: doc.returns.type,
				};
		}
		return { kind: 'function', params: [], return: UNKNOWN };
	}

	return UNKNOWN;
}

// ── Scope building ─────────────────────────────────────────────────────────

function importScope(uri) {
	let scope = makeScope(null);
	let imps = dag.importsOf(uri);
	if (!imps) return scope;
	for (let i = 0; i < length(imps); i++) {
		let imp = imps[i];
		if (imp.alias || !imp.resolvedUri) continue;
		let exps = dag.exportsOf(imp.resolvedUri);
		if (!exps) continue;
		for (let j = 0; j < length(exps); j++) {
			let exp = exps[j];
			if (index(imp.symbols, exp.name) >= 0)
				scopeSet(scope, exp.name, exportType(exp));
		}
	}
	return scope;
}

// Build a scope for the given file at targetOffset: imports + all
// let/const declarations that appear before targetOffset.
export function buildScope(uri, source, tree, targetOffset) {
	let scope = importScope(uri);
	let root = ts.rootNode(tree);
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.startByte(stmt) >= targetOffset) break;
		if (ts.nodeType(stmt) === 'lexical_declaration')
			processDecl(stmt, source, uri, scope, 0);
	}
	return scope;
};

// ── Public API ────────────────────────────────────────────────────────────

_infer = function(node, source, uri, scope, depth) {
	if (!node || depth > 10) return UNKNOWN;

	let offset = ts.startByte(node);
	let cached = memoGet(uri, offset);
	if (cached) return cached;

	let type = inferInner(node, source, uri, scope, depth);
	memoSet(uri, offset, type);
	return type;
};

export function inferNode(node, source, uri, scope, depth) {
	return _infer(node, source, uri, scope, depth ?? 0);
};
