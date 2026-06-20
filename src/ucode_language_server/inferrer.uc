import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag';
import { parseDoc } from 'ucode_language_server.doc_parser';
import { unify, substitute } from 'ucode_language_server.type_unifier';
import { memoGet, memoSet } from 'ucode_language_server.memo';
import { makeScope, scopeGet, scopeSet } from 'ucode_language_server.scope';
import * as type_registry from 'ucode_language_server.type_registry';

let UNKNOWN = { kind: 'unknown' };
let BOOL    = { kind: 'primitive', name: 'boolean' };
let STR     = { kind: 'primitive', name: 'string' };
let INT     = { kind: 'primitive', name: 'int' };
let NULL_T  = { kind: 'primitive', name: 'null' };

// ── Builtin scope ─────────────────────────────────────────────────────────

function _initBuiltins() {
	let s    = makeScope(null);
	let FLOAT = { kind: 'primitive', name: 'float' };
	let ANY   = { kind: 'any' };
	let LIST  = { kind: 'generic', base: 'list', params: [ANY] };
	let LSTR  = { kind: 'generic', base: 'list', params: [STR] };

	function fn0(r) { return { kind: 'function', params: [], return: r }; }
	function fn1(r) { return { kind: 'function', params: [{ name: 'a', type: ANY }], return: r }; }
	function fn2(r) { return { kind: 'function', params: [{ name: 'a', type: ANY }, { name: 'b', type: ANY }], return: r }; }
	function fn3(r) { return { kind: 'function', params: [{ name: 'a', type: ANY }, { name: 'b', type: ANY }, { name: 'c', type: ANY }], return: r }; }

	// Strings
	scopeSet(s, 'sprintf', fn2(STR));   scopeSet(s, 'trim',  fn1(STR));
	scopeSet(s, 'ltrim',   fn1(STR));   scopeSet(s, 'rtrim', fn1(STR));
	scopeSet(s, 'lc',      fn1(STR));   scopeSet(s, 'uc',    fn1(STR));
	scopeSet(s, 'substr',  fn3(STR));   scopeSet(s, 'join',  fn2(STR));
	scopeSet(s, 'split',   fn2(LSTR));
	// Arrays
	scopeSet(s, 'push',    fn2(NULL_T));  scopeSet(s, 'pop',     fn1(ANY));
	scopeSet(s, 'shift',   fn1(ANY));     scopeSet(s, 'unshift', fn2(NULL_T));
	scopeSet(s, 'splice',  fn3(LIST));    scopeSet(s, 'slice',   fn3(LIST));
	scopeSet(s, 'reverse', fn1(NULL_T));  scopeSet(s, 'sort',    fn2(LIST));
	scopeSet(s, 'index',   fn2(INT));     scopeSet(s, 'length',  fn1(INT));
	scopeSet(s, 'map',     fn2(LIST));    scopeSet(s, 'filter',  fn2(LIST));
	scopeSet(s, 'reduce',  fn3(ANY));
	// Objects
	scopeSet(s, 'keys',    fn1(LSTR));   scopeSet(s, 'values', fn1(LIST));
	scopeSet(s, 'delete',  fn2(NULL_T));
	// Types
	scopeSet(s, 'type',    fn1(STR));    scopeSet(s, 'int',    fn1(INT));
	scopeSet(s, 'string',  fn1(STR));    scopeSet(s, 'float',  fn1(FLOAT));
	scopeSet(s, 'bool',    fn1(BOOL));
	// Math
	scopeSet(s, 'abs',   fn1(FLOAT));  scopeSet(s, 'ceil',  fn1(INT));
	scopeSet(s, 'floor', fn1(INT));    scopeSet(s, 'rand',  fn0(FLOAT));
	scopeSet(s, 'srand', fn1(NULL_T)); scopeSet(s, 'sqrt',  fn1(FLOAT));
	scopeSet(s, 'atan2', fn2(FLOAT));  scopeSet(s, 'sin',   fn1(FLOAT));
	scopeSet(s, 'cos',   fn1(FLOAT));  scopeSet(s, 'log',   fn1(FLOAT));
	scopeSet(s, 'exp',   fn1(FLOAT));  scopeSet(s, 'pow',   fn2(FLOAT));
	// IO
	scopeSet(s, 'print',  fn1(NULL_T));  scopeSet(s, 'printf', fn2(NULL_T));
	scopeSet(s, 'warn',   fn1(NULL_T));  scopeSet(s, 'die',    fn1(NULL_T));
	// Other
	scopeSet(s, 'json',   fn1(ANY));    scopeSet(s, 'ord',  fn1(INT));
	scopeSet(s, 'chr',    fn1(STR));    scopeSet(s, 'hex',  fn1(INT));
	scopeSet(s, 'match',  fn2({ kind: 'nullable', inner: LSTR }));
	scopeSet(s, 'regexp', fn1(ANY));

	return s;
}

let _builtinScope = _initBuiltins();

// ── Helpers ────────────────────────────────────────────────────────────────

// Return the text of the /** */ comment immediately before `node` among its
// direct parent's children. Any intervening named node or // comment resets.
function docForFunc(node, source) {
	let parent = ts.parent(node);
	if (!parent) return null;
	let nodeStart = ts.startByte(node);
	let children = ts.children(parent);
	let found = null;
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.startByte(c) >= nodeStart) break;
		if (ts.nodeType(c) === 'comment') {
			let txt = ts.text(c, source);
			found = (substr(txt, 0, 3) === '/**') ? txt : null;
		} else if (ts.isNamed(c)) {
			found = null;
		}
	}
	return found;
}

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

// Add the formal parameters of fn to scope. Types come from the function's
// JSDoc @param annotations when present.
function addParamScope(fn, source, scope) {
	let docTxt = docForFunc(fn, source);
	let docParams = (docTxt ? parseDoc(docTxt).params : null) ?? [];

	function paramType(name) {
		for (let k = 0; k < length(docParams); k++)
			if (docParams[k].name === name && docParams[k].type) return docParams[k].type;
		return UNKNOWN;
	}

	let foundFormal = false;
	for (let i = 0; i < ts.namedChildCount(fn); i++) {
		let child = ts.namedChild(fn, i);
		if (ts.nodeType(child) !== 'formal_parameters') continue;
		foundFormal = true;
		for (let j = 0; j < ts.namedChildCount(child); j++) {
			let param = ts.namedChild(child, j);
			if (ts.nodeType(param) !== 'identifier') continue;
			let name = ts.text(param, source);
			scopeSet(scope, name, paramType(name));
		}
		break;
	}

	// Single-param arrow `x => ...` has a bare identifier as param, no formal_parameters node.
	if (!foundFormal && ts.nodeType(fn) === 'arrow_function') {
		let first = ts.namedChild(fn, 0);
		if (first && ts.nodeType(first) === 'identifier') {
			let name = ts.text(first, source);
			scopeSet(scope, name, paramType(name));
		}
	}
}

// Look up a member name in a resolved type. Expands ref types via the registry.
function memberOfType(type, propName) {
	if (!type) return UNKNOWN;
	if (type.kind === 'record') {
		for (let i = 0; i < length(type.fields); i++)
			if (type.fields[i].name === propName) return type.fields[i].type;
		return UNKNOWN;
	}
	if (type.kind === 'ref') {
		let def = type_registry.lookup(type.name);
		if (def) return memberOfType(def.type, propName);
	}
	return UNKNOWN;
}

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
	let ret = UNKNOWN;
	if (bodyNode) {
		if (ts.nodeType(bodyNode) === 'statement_block') {
			// Scan direct children for the first return statement.
			for (let i = 0; i < ts.namedChildCount(bodyNode); i++) {
				let child = ts.namedChild(bodyNode, i);
				if (ts.nodeType(child) !== 'return_statement') continue;
				let expr = ts.namedChild(child, 0);
				if (expr) ret = _infer(expr, source, uri, childScope, depth + 1);
				break;
			}
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
	// General: infer the object's type, then walk the member in it.
	// Depth is threaded to prevent runaway recursion on pathological chains.
	let objType = _infer(objNode, source, uri, scope, (depth ?? 0) + 1);
	if (objType && objType.kind !== 'unknown')
		return memberOfType(objType, propName);
	return UNKNOWN;
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

	// Cursor on a property name in obj.prop — infer the whole member expression.
	if (ntype === 'property_identifier') {
		let parent = ts.parent(node);
		if (parent && ts.nodeType(parent) === 'member_expression')
			return inferMember(parent, source, uri, scope, depth);
		return UNKNOWN;
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
		let n = ts.namedChildCount(node);
		if (n === 0) return { kind: 'generic', base: 'list', params: [UNKNOWN] };
		// Collect distinct element types; build a union when they differ.
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

	if (ntype === 'object') {
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

	if (ntype === 'call_expression')   return inferCall(node, source, uri, scope, depth);
	if (ntype === 'member_expression') return inferMember(node, source, uri, scope, depth);
	if (ntype === 'arrow_function') return inferArrow(node, source, uri, scope, depth, null);

	if (ntype === 'function_expression') {
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
		return inferArrow(node, source, uri, scope, depth, null);
	}

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
		// No JSDoc @returns — infer from body's first return statement.
		let body = ts.childByField(node, 'body');
		let ret = UNKNOWN;
		if (body) {
			for (let i = 0; i < ts.namedChildCount(body); i++) {
				let child = ts.namedChild(body, i);
				if (ts.nodeType(child) !== 'return_statement') continue;
				let expr = ts.namedChild(child, 0);
				if (expr) ret = _infer(expr, source, uri, scope, depth + 1);
				break;
			}
		}
		return { kind: 'function', params: [], return: ret };
	}

	return UNKNOWN;
}

// ── Scope building ─────────────────────────────────────────────────────────

function importScope(uri) {
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

// Process declarations in a block of statements into scope, stopping at targetOffset.
// Handles let/const, for-in loop vars, and assignment updates — same logic
// whether the block is the top-level program or a function body.
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
				scopeSet(scope, ts.text(nameNode, source), _infer(stmt, source, uri, scope, 0));

		} else if (stype === 'export_statement') {
			let inner = ts.namedChild(stmt, 0);
			if (inner && ts.nodeType(inner) === 'lexical_declaration')
				processDecl(inner, source, uri, scope, 0);

		} else if (stype === 'for_in_statement') {
			if (targetOffset < ts.endByte(stmt)) {
				let loopVar = ts.childByField(stmt, 'left');
				if (loopVar && ts.nodeType(loopVar) === 'identifier') {
					let iterable = ts.childByField(stmt, 'right');
					let elemType = UNKNOWN;
					if (iterable) {
						let iterType = _infer(iterable, source, uri, scope, 0);
						if (iterType.kind === 'generic' && iterType.base === 'list' && length(iterType.params) > 0)
							elemType = iterType.params[0];
						else if (iterType.kind === 'record')
							elemType = STR;  // for-in over an object iterates string keys
					}
					scopeSet(scope, ts.text(loopVar, source), elemType);
				}
			}

		} else if (stype === 'expression_statement') {
			let inner = ts.namedChild(stmt, 0);
			if (inner && ts.nodeType(inner) === 'assignment_expression') {
				let lhs = ts.childByField(inner, 'left');
				let rhs = ts.childByField(inner, 'right');
				if (lhs && rhs && ts.nodeType(lhs) === 'identifier') {
					let name = ts.text(lhs, source);
					if (scopeGet(scope, name) !== null)
						scopeSet(scope, name, _infer(rhs, source, uri, scope, 0));
				}
			}
		}
	}
}

// Build a scope for the given file at targetOffset: imports + top-level
// declarations + parameters and body declarations of all enclosing functions
// (outermost first, so inner names shadow outer ones).
export function buildScope(uri, source, tree, targetOffset) {
	let scope = importScope(uri);
	let root = ts.rootNode(tree);

	processBlock(ts.namedChildren(root), source, uri, scope, targetOffset);

	let fns = enclosingFunctions(root, targetOffset);
	for (let i = 0; i < length(fns); i++) {
		addParamScope(fns[i], source, scope);
		let body = ts.childByField(fns[i], 'body');
		if (body) processBlock(ts.namedChildren(body), source, uri, scope, targetOffset);
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
