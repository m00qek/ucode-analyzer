import * as ts from 'tree_sitter';
import { isStatementList } from 'code_analysis.positions';
import { firstNamed } from 'code_analysis.ast_text';

// The variable_declarator name node for `name` inside a lexical_declaration
// (or a `for (let x …)` binding), or null.
function declaratorName(declNode, name, text) {
	for (let j = 0; j < ts.namedChildCount(declNode); j++) {
		let vd = ts.namedChild(declNode, j);
		if (ts.nodeType(vd) !== 'variable_declarator') continue;
		let nn = ts.childByField(vd, 'name');
		if (nn && ts.text(nn, text) === name) return nn;
	}
	return null;
}

// True if a for-in header declares its loop variable(s) — `for (let k in …)` —
// rather than assigning to a pre-existing binding — `for (x in …)`. The `let`/
// `const` keyword is an anonymous child token of the for node.
function forInDeclares(node, text) {
	for (let i = 0; i < ts.childCount(node); i++) {
		let c = ts.child(node, i);
		if (ts.isNamed(c)) continue;
		let s = ts.text(c, text);
		if (s === 'let' || s === 'const') return true;
	}
	return false;
}

// If `scopeNode` binds `name`, return the binding identifier node. Covers every
// local binder: block-level let/const and nested function declarations, function
// parameters, for-in / C-for loop variables, and catch parameters.
function binderIn(scopeNode, name, text) {
	let nt = ts.nodeType(scopeNode);

	if (isStatementList(nt)) {
		for (let i = 0; i < ts.namedChildCount(scopeNode); i++) {
			let stmt = ts.namedChild(scopeNode, i);
			let st = ts.nodeType(stmt);
			if (st === 'lexical_declaration') {
				let nn = declaratorName(stmt, name, text);
				if (nn) return nn;
			} else if (st === 'function_declaration') {
				let nn = ts.childByField(stmt, 'name');
				if (nn && ts.text(nn, text) === name) return nn;
			}
		}
		return null;
	}

	if (nt === 'function_declaration' || nt === 'function_expression' || nt === 'arrow_function') {
		let params = ts.childByField(scopeNode, 'parameters');
		if (params)
			for (let j = 0; j < ts.namedChildCount(params); j++) {
				let p = ts.namedChild(params, j);
				if (ts.nodeType(p) === 'identifier' && ts.text(p, text) === name) return p;
				// rest parameter: `...args` — the name is the identifier under it.
				if (ts.nodeType(p) === 'rest_element') {
					let id = firstNamed(p);
					if (id && ts.nodeType(id) === 'identifier' && ts.text(id, text) === name) return id;
				}
			}
		// arrow with a single bare parameter: `x => …`
		let bare = ts.childByField(scopeNode, 'parameter');
		if (bare && ts.nodeType(bare) === 'identifier' && ts.text(bare, text) === name) return bare;
		return null;
	}

	if (nt === 'for_in_statement' || nt === 'for_in_alt_statement') {
		// `for (x in y)` (no let/const) assigns to a binding declared elsewhere,
		// so this node does not bind `name` — let the real declaration win.
		if (!forInDeclares(scopeNode, text)) return null;
		// `for (let x in obj)` binds `variable`; `for (let k, v in obj)` binds `key` and `value`.
		for (let f in ['variable', 'key', 'value']) {
			let v = ts.childByField(scopeNode, f);
			if (v && ts.nodeType(v) === 'identifier' && ts.text(v, text) === name) return v;
		}
		return null;
	}

	if (nt === 'for_statement' || nt === 'for_alt_statement') {
		let init = ts.childByField(scopeNode, 'initializer');
		if (init && ts.nodeType(init) === 'lexical_declaration')
			return declaratorName(init, name, text);
		return null;
	}

	if (nt === 'catch_clause') {
		let param = ts.childByField(scopeNode, 'parameter');
		if (param && ts.nodeType(param) === 'identifier' && ts.text(param, text) === name)
			return param;
		return null;
	}

	return null;
}

// The identifier that declares `name` in the lexical scope at `offset`, or null.
// Descends the tree by offset (a template's code nests exactly like a script's,
// its root `markup` playing `program`'s part), then walks the resulting ancestor chain innermost-first so the nearest
// binding wins (closures capture outer-function locals, so outer scopes count).
export function localBinding(root, name, offset, text) {
	let chain = [];
	let node  = root;
	while (node) {
		push(chain, node);
		let next = null;
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let c = ts.namedChild(node, i);
			if (ts.startByte(c) <= offset && offset < ts.endByte(c)) { next = c; break; }
		}
		node = next;
	}
	for (let k = length(chain) - 1; k >= 0; k--) {
		let hit = binderIn(chain[k], name, text);
		if (hit) return hit;
	}
	return null;
};
