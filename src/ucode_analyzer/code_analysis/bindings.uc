import * as ts from 'tree_sitter';
import { isStatementList } from 'ucode_analyzer.code_analysis.positions';
import { declarators, paramNodes, namedNonComments } from 'ucode_analyzer.code_analysis.ast_text';
import { importBindingNodes } from 'ucode_analyzer.code_analysis.mode';

// The variable_declarator name node for `name` inside a lexical_declaration
// (or a `for (let x …)` binding), or null.
function declaratorName(declNode, name, text) {
	for (let vd in declarators(declNode)) {
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
		for (let p in paramNodes(scopeNode))
			if (ts.text(p.node, text) === name) return p.node;
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

// ── Names in scope order ────────────────────────────────────────────────────
// A walk for analyses that need only which declaration a name means, not its
// type: undefined_var (is a use declared?) and scope_references (which
// declaration does it mean?). Each scope maps a name to the start byte of the
// identifier declaring it.

function nameScope(parent) {
	return { names: {}, parent };
}

// The start byte of the identifier declaring `name` in scope, or -1.
export function declarationOf(scope, name) {
	for (let s = scope; s; s = s.parent)
		if (exists(s.names, name)) return s.names[name];
	return -1;
};

let walkNames;

function declare(scope, node, source, visitor) {
	let name = ts.text(node, source);
	scope.names[name] = ts.startByte(node);
	visitor.declare(node, name);
}

function walkFunction(node, scope, source, visitor) {
	let inner = nameScope(scope);
	// A named function expression sees its own name.
	let name = (ts.nodeType(node) === 'function_expression') ? ts.childByField(node, 'name') : null;
	if (name && ts.nodeType(name) === 'identifier') declare(inner, name, source, visitor);
	for (let p in paramNodes(node)) declare(inner, p.node, source, visitor);
	let body = ts.childByField(node, 'body');
	if (body) walkNames(body, inner, source, visitor);
}

function walkForIn(node, scope, source, visitor) {
	let object = ts.childByField(node, 'object');
	if (object) walkNames(object, scope, source, visitor);
	let inner = nameScope(scope);
	// `for (let k, v in o)` declares; `for (x in o)` assigns an existing x.
	let declares = forInDeclares(node, source);
	for (let field in ['variable', 'key', 'value']) {
		let v = ts.childByField(node, field);
		if (!v || ts.nodeType(v) !== 'identifier') continue;
		if (declares)
			declare(inner, v, source, visitor);
		else
			visitor.use(v, ts.text(v, source), scope);
	}
	let body = ts.childByField(node, 'body');
	if (body) walkNames(body, inner, source, visitor);
}

function walkFor(node, scope, source, visitor) {
	let inner = nameScope(scope);
	let init = ts.childByField(node, 'initializer');
	if (init && ts.nodeType(init) === 'lexical_declaration') {
		// Each initializer sees the declarators before it (`let i = 0, x = xs[i]`).
		for (let vd in declarators(init)) {
			let value = ts.childByField(vd, 'value');
			if (value) walkNames(value, inner, source, visitor);
			let name = ts.childByField(vd, 'name');
			if (name && ts.nodeType(name) === 'identifier') declare(inner, name, source, visitor);
		}
	} else if (init) {
		walkNames(init, scope, source, visitor);
	}
	for (let field in ['condition', 'increment', 'body']) {
		let part = ts.childByField(node, field);
		if (part) walkNames(part, inner, source, visitor);
	}
}

function walkUse(node, scope, source, visitor) {
	visitor.use(node, ts.text(node, source), scope);
}

function walkChildren(node, scope, source, visitor) {
	for (let c in ts.namedChildren(node)) walkNames(c, scope, source, visitor);
}

// The node types walked other than by their children, by type: a table, as
// most nodes are none of these.
const WALKERS = {
	identifier: walkUse,
	shorthand_property_identifier: walkUse,
	import_statement: (node, scope, source, visitor) => {
		for (let n in importBindingNodes(node)) declare(scope, n, source, visitor);
	},
	lexical_declaration: (node, scope, source, visitor) => {
		for (let vd in declarators(node)) {
			let name = ts.childByField(vd, 'name');
			if (name) declare(scope, name, source, visitor);
			let value = ts.childByField(vd, 'value');
			if (value) walkNames(value, scope, source, visitor);
		}
	},
	function_declaration: (node, scope, source, visitor) => {
		let name = ts.childByField(node, 'name');
		if (name && ts.nodeType(name) === 'identifier') declare(scope, name, source, visitor);
		walkFunction(node, scope, source, visitor);
	},
	function_expression: walkFunction,
	arrow_function: walkFunction,
	export_statement: (node, scope, source, visitor) => {
		for (let inner in namedNonComments(node)) walkNames(inner, scope, source, visitor);
	},
	// `export { a as b }` uses a; b is only the exported name.
	export_specifier: (node, scope, source, visitor) => {
		let name = ts.childByField(node, 'name');
		if (name) walkNames(name, scope, source, visitor);
	},
	catch_clause: (node, scope, source, visitor) => {
		let inner = nameScope(scope);
		let param = ts.childByField(node, 'parameter');
		if (param && ts.nodeType(param) === 'identifier') declare(inner, param, source, visitor);
		let body = ts.childByField(node, 'body');
		if (body) walkNames(body, inner, source, visitor);
	},
	statement_block: (node, scope, source, visitor) => walkChildren(node, nameScope(scope), source, visitor),
	statement_list: (node, scope, source, visitor) => walkChildren(node, nameScope(scope), source, visitor),
	for_in_statement: walkForIn,
	for_in_alt_statement: walkForIn,
	for_statement: walkFor,
	for_alt_statement: walkFor,
	// `o.p`: p is a property name, not a use.
	member_expression: (node, scope, source, visitor) => {
		let object = ts.childByField(node, 'object');
		if (object) walkNames(object, scope, source, visitor);
	},
};

// Walk `node` with the names of `scope` declared, calling visitor.declare(node,
// name) where a name enters scope and visitor.use(node, name, scope) for every
// use: an identifier, or a shorthand property `{ x }` (which uses x). There is
// no hoisting: a name is declared where its statement is.
walkNames = function(node, scope, source, visitor) {
	(WALKERS[ts.nodeType(node)] ?? walkChildren)(node, scope, source, visitor);
};

// Walk a whole tree; see walkNames.
export function eachName(root, source, visitor) {
	walkNames(root, nameScope(null), source, visitor);
};
