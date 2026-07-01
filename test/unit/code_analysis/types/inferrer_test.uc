import { describe, it, assert, mock, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'code_analysis.dag.dag';
import { inferNode } from 'code_analysis.types.inferrer';
import { initBuiltinsFromDag } from 'code_analysis.types.dag_bridge';
import { buildScopeMap, scopeAtOffset } from 'code_analysis.types.scope_walk';
import { makeScope, scopeSet, scopeGet } from 'code_analysis.types.scope';
import { invalidateUri } from 'code_analysis.memo';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

let URI = 'file:///app/src/test_main.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

// Bootstrap the builtin scope from stdlib.d.uc once for the whole test run.
dag.init(_config);
let _globalUri = dag.resolveSpecifier('global');
if (_globalUri) {
	dag.addFromDisk(_globalUri);
	initBuiltinsFromDag(_globalUri);
}

beforeEach(() => {
	dag.init(_config);
	dag.remove(URI);
	invalidateUri(URI);
});

// Parse text and return the value node of the first variable_declarator.
// For `let x = <expr>;` this returns the <expr> node.
function exprNode(text) {
	let tree = parse(text);
	let root = ts.rootNode(tree);
	let stmt = ts.namedChild(root, 0);  // lexical_declaration
	let decl = ts.namedChild(stmt, 0);  // variable_declarator
	return ts.childByField(decl, 'value');
}

function infer(text) {
	let node = exprNode(text);
	return inferNode(node, text, URI, makeScope(null), 0);
}

function scopeFor(text, tree, offset) {
	return scopeAtOffset(buildScopeMap(URI, text, tree), offset);
}

function prim(name)       { return { kind: 'primitive', name }; }
function list_(elem)      { return { kind: 'generic', base: 'list', params: [elem] }; }
function unknown()        { return { kind: 'unknown' }; }
function union_(a, b)     { return { kind: 'union', members: [a, b] }; }

describe('inferrer — literals', () => {
	it('infers integer', () => {
		assert.match(prim('int'), infer('let x = 42;'));
	});

	it('infers float', () => {
		assert.match(prim('float'), infer('let x = 3.14;'));
	});

	it('infers string', () => {
		assert.match(prim('string'), infer("let x = 'hello';"));
	});

	it('infers template string', () => {
		assert.match(prim('string'), infer('let x = `world`;'));
	});

	it('infers true', () => {
		assert.match(prim('boolean'), infer('let x = true;'));
	});

	it('infers false', () => {
		assert.match(prim('boolean'), infer('let x = false;'));
	});

	it('infers null', () => {
		assert.match(prim('null'), infer('let x = null;'));
	});
});

describe('inferrer — binary expressions', () => {
	it('== yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = 1 == 2;'));
	});

	it('=== yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = 1 === 2;'));
	});

	it('!== yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = 1 !== 2;'));
	});

	it('< yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = 1 < 2;'));
	});

	it('&& yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = true && false;'));
	});

	it('int + int yields int', () => {
		assert.match(prim('int'), infer('let x = 1 + 2;'));
	});

	it('string + string yields string', () => {
		assert.match(prim('string'), infer("let x = 'a' + 'b';"));
	});

	it('int + string yields string', () => {
		assert.match(prim('string'), infer("let x = 1 + 'a';"));
	});

	it('arithmetic on float yields float', () => {
		assert.match(prim('float'), infer('let x = 1.5 * 2;'));
	});

	it('arithmetic: int op float yields float (float on right)', () => {
		assert.match(prim('float'), infer('let x = 2 * 1.5;'));
	});
});

describe('inferrer — unary expressions', () => {
	it('! yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = !true;'));
	});

	it('unary minus on int yields int', () => {
		assert.match(prim('int'), infer('let x = -1;'));
	});
});

describe('inferrer — ternary expressions', () => {
	it('same-type branches return that type', () => {
		assert.match(prim('int'), infer('let x = true ? 1 : 2;'));
	});

	it('different-type branches return union', () => {
		assert.match(union_(prim('int'), prim('string')), infer("let x = true ? 1 : 'a';"));
	});
});

describe('inferrer — array literals', () => {
	it('empty array yields list<unknown>', () => {
		assert.match(list_(unknown()), infer('let x = [];'));
	});

	it('integer array yields list<int>', () => {
		assert.match(list_(prim('int')), infer('let x = [1, 2, 3];'));
	});

	it('mixed int/string array yields list<int | string>', () => {
		let t = infer("let x = [1, 'a'];");
		assert.match('generic', t.kind);
		assert.match('list', t.base);
		assert.match('union', t.params[0].kind);
		assert.match(2, length(t.params[0].members));
	});

	it('single-element array yields list<T>, not a union', () => {
		let t = infer('let x = [42];');
		assert.match(list_(prim('int')), t);
	});
});

describe('inferrer — identifier and scope', () => {
	it('unknown identifier yields unknown', () => {
		let node = exprNode('let x = y;');
		let result = inferNode(node, 'let x = y;', URI, makeScope(null), 0);
		assert.match(unknown(), result);
	});

	it('identifier bound in scope yields its type', () => {
		let s = makeScope(null);
		scopeSet(s, 'y', prim('string'));
		let node = exprNode('let x = y;');
		let result = inferNode(node, 'let x = y;', URI, s, 0);
		assert.match(prim('string'), result);
	});
});

describe('inferrer — block-body function return type inference', () => {
	it('infers return type from first return statement in a block body arrow', () => {
		let t = infer('let f = (x) => { return 42; };');
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});

	it('infers return type from first return statement in a function_declaration', () => {
		let text = "function greet() { return 'hello'; }";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let fnNode = ts.namedChild(root, 0);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);
		let t = inferNode(fnNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});

	it('bare-expression arrow body still works', () => {
		let t = infer('let f = x => x + 1;');
		assert.match('function', t.kind);
		// return is unknown because x has no known type here
	});
});

describe('inferrer — arrow functions', () => {
	it('single-param arrow has one param and inferred return', () => {
		let result = infer('let f = x => 42;');
		assert.match('function', result.kind);
		assert.match(prim('int'), result.return);
		assert.match(1, length(result.params));
		assert.match('x', result.params[0].name);
	});

	it('multi-param arrow has correct param names and inferred return', () => {
		let result = infer('let f = (a, b) => true;');
		assert.match('function', result.kind);
		assert.match(prim('boolean'), result.return);
		assert.match(2, length(result.params));
		assert.match('a', result.params[0].name);
		assert.match('b', result.params[1].name);
	});

	it('arrow body referring to unknown param yields unknown return', () => {
		// No pushed-down type context → param type is unknown → body `a` is unknown
		let result = infer('let f = a => a;');
		assert.match('function', result.kind);
		assert.match(unknown(), result.return);
	});

	it('arrow with literal body ignores param type', () => {
		let result = infer("let f = x => 'hi';");
		assert.match('function', result.kind);
		assert.match(prim('string'), result.return);
	});
});

describe('inferrer — call expressions', () => {
	it('call of in-scope function returns its declared return type', () => {
		// Build a scope where `greet` is typed as () -> string
		let s = makeScope(null);
		scopeSet(s, 'greet', { kind: 'function', params: [], return: prim('string') });
		// Parse a call expression
		let text = "let r = greet();";
		let node = exprNode(text);
		let result = inferNode(node, text, URI, s, 0);
		assert.match(prim('string'), result);
	});

	it('call of unknown function yields unknown', () => {
		let result = infer('let r = foo();');
		assert.match(unknown(), result);
	});
});

describe('inferrer — buildScope', () => {
	it('binds preceding let declarations into scope', () => {
		let text = "let a = 1;\nlet b = 'hello';\nlet c = b;";
		let tree = parse(text);
		let root = ts.rootNode(tree);

		// Point at the third statement (let c = b); only a and b should be in scope.
		let thirdStmt = ts.namedChild(root, 2);
		let offset = ts.startByte(thirdStmt);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'a'));
		assert.match(prim('string'), scopeGet(scope, 'b'));
		assert.match(null, scopeGet(scope, 'c'));
	});

	it('includes function parameters for an offset inside a function body', () => {
		// Offset inside the body: after the opening brace, before the return.
		// 'x' is a parameter; it should appear in scope with unknown type (no JSDoc).
		let text = "function add(x, y) {\nreturn x + y;\n}";
		let tree = parse(text);
		// Position of 'x' reference on line 1 (inside the body)
		let offset = length("function add(x, y) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		// Parameters must be in scope (even without JSDoc the bindings key exists)
		assert.match(true, scopeGet(scope, 'x') !== null);
		assert.match(true, scopeGet(scope, 'y') !== null);
	});

	it('uses JSDoc @param types when present', () => {
		let text = "/** @param {int} n — count */\nfunction double(n) {\nreturn n * 2;\n}";
		let tree = parse(text);
		let offset = length("/** @param {int} n — count */\nfunction double(n) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'n'));
	});

	it('single-param arrow parameter is in scope inside the body', () => {
		let text = "let f = x => x + 1;";
		let tree = parse(text);
		// Offset inside the arrow body (at `x` in `x + 1`)
		let offset = length("let f = x => ");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(true, scopeGet(scope, 'x') !== null);
	});

	it('inner parameters shadow outer ones of the same name', () => {
		let text = "function outer(x) {\nfunction inner(x) {\nreturn x;\n}\n}";
		let tree = parse(text);
		// Offset inside inner(): after 'return '
		let offset = length("function outer(x) {\nfunction inner(x) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		// The binding for 'x' should exist (the inner one wins — same key, last write wins)
		assert.match(true, scopeGet(scope, 'x') !== null);
	});
});

describe('inferrer — buildScope: export let', () => {
	it('export let declarations are in scope', () => {
		let text = "export let count = 42;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'count'));
	});
});

describe('inferrer — buildScope: export function', () => {
	it('export function declarations are in scope for later references', () => {
		let text = "/**\n * @returns {string}\n */\nexport function tag(x) {}\nexport function caller(v) {\n    let r = tag(v);\n    r;\n}\n";
		let tree = parse(text);
		// offset at 'r;' inside caller
		let offset = index(text, '\n    r;') + 5;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(true, scopeGet(scope, 'tag') !== null);
		assert.match(prim('string'), scopeGet(scope, 'r'));
	});
});

describe('inferrer — buildScope: namespace import alias', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	it('namespace alias is in scope as module type', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'ts');
		assert.match(true, t !== null);
		assert.match('module', t.kind);
		assert.match('tree_sitter', t.path);
	});
});

describe('inferrer — buildScope: for_in loop variable', () => {
	it('loop variable is bound inside a for-in body', () => {
		let text = "let items = [1, 2, 3];\nfor (let it in items) {\nit;\n}";
		let tree = parse(text);
		// Offset at 'it' reference inside the for body
		let offset = length("let items = [1, 2, 3];\nfor (let it in items) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(true, scopeGet(scope, 'it') !== null);
		// items is list<int>, so element type is int
		assert.match(prim('int'), scopeGet(scope, 'it'));
	});

	it('loop variable over a record literal is string (key iteration)', () => {
		let text = "let m = { a: 1, b: 2 };\nfor (let k in m) {\nk;\n}";
		let tree = parse(text);
		let offset = length("let m = { a: 1, b: 2 };\nfor (let k in m) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'k'));
	});

	it('loop variable is not in scope after the for-in statement', () => {
		let text = "for (let k in [1]) {}\nk;\n";
		let tree = parse(text);
		let offset = length(text) - 2;  // at 'k' after the for

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(null, scopeGet(scope, 'k'));
	});
});

describe('inferrer — buildScope: nested block scope', () => {
	it('let inside a for-in body is bound', () => {
		let text = "/**\n * @returns {string}\n */\nfunction f(x) { return x; }\nfor (let it in arr) {\n    let k = f(it);\n    k;\n}";
		let tree = parse(text);
		let offset = index(text, '\n    k;') + 5;  // at standalone 'k'

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'k'));
	});

	it('let inside a nested for-in body is bound', () => {
		let text = "/**\n * @returns {string}\n */\nfunction f(x) { return x; }\nfor (let outer in arr) {\n    for (let node in outer) {\n        let k = f(node);\n        k;\n    }\n}";
		let tree = parse(text);
		let offset = index(text, '\n        k;') + 9;  // at standalone 'k'

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'k'));
	});

	it('let inside an if-body is bound', () => {
		let text = "/**\n * @returns {string}\n */\nfunction f(x) { return x; }\nif (cond) {\n    let k = f(v);\n    k;\n}";
		let tree = parse(text);
		let offset = index(text, '\n    k;') + 5;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'k'));
	});

	it('let inside a while-body is bound', () => {
		let text = "/**\n * @returns {string}\n */\nfunction f(x) { return x; }\nwhile (cond) {\n    let k = f(v);\n    k;\n}";
		let tree = parse(text);
		let offset = index(text, '\n    k;') + 5;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'k'));
	});
});

describe('inferrer — buildScope: assignment expression', () => {
	it('updates a declared variable type on assignment', () => {
		// x starts as string (from the literal), then gets reassigned to int
		let text = "let x = 'hello';\nx = 42;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'x'));
	});

	it('does not create a new binding for undeclared identifiers', () => {
		let text = "undeclared = 5;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(null, scopeGet(scope, 'undeclared'));
	});
});

describe('inferrer — object literals', () => {
	it('infers a record type from an object literal, with literal field values', () => {
		let t = infer('let o = { a: 1, b: "hi" };');
		assert.match('record', t.kind);
		assert.match(2, length(t.fields));
		assert.match('a', t.fields[0].name);
		// String/number literal field values carry their concrete value.
		assert.match({ kind: 'primitive', name: 'int', value: 1 }, t.fields[0].type);
		assert.match('b', t.fields[1].name);
		assert.match({ kind: 'primitive', name: 'string', value: 'hi' }, t.fields[1].type);
	});

	it('does not attach a literal value to a non-literal field expression', () => {
		let t = infer('let o = { a: 1 + 2 };');
		assert.match(prim('int'), t.fields[0].type);  // computed → widened base, no value
	});

	it('infers an empty record for an empty object', () => {
		let t = infer('let o = {};');
		assert.match('record', t.kind);
		assert.match(0, length(t.fields));
	});
});

describe('inferrer — JSDoc on nested function declarations', () => {
	it('picks up the doc immediately before the inner function, not the outer', () => {
		let text = "/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nfunction inner() { return 1; }\ninner;\n}";
		let tree = parse(text);
		let offset = length("/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nfunction inner() { return 1; }\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'inner');
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});

	it('nested function_expression uses doc before its let, not the enclosing function doc', () => {
		let text = "/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\nf;\n}";
		let tree = parse(text);
		let offset = length("/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'f');
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});
});

describe('inferrer — function_expression', () => {
	it('infers a function type from body', () => {
		let t = infer('let f = function(a) { return 1; };');
		assert.match('function', t.kind);
	});

	it('named function_expression: params are not confused with function name', () => {
		// Regression: inferArrow used namedChild(0) which is the name identifier
		// for named function_expressions, treating it as a single param.
		let text = "let f = function myFunc(a, b) { return a; };";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let stmt = ts.namedChild(root, 0);
		let decl = ts.namedChild(stmt, 0);
		let fnNode = ts.childByField(decl, 'value');

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, ts.startByte(fnNode));
		let t = inferNode(fnNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		// Should have 2 params (a, b), not 1 param ('myFunc')
		assert.match(2, length(t.params));
		assert.match('a', t.params[0].name);
		assert.match('b', t.params[1].name);
	});

	it('uses JSDoc @returns when present', () => {
		let text = "/** @param {int} n\n * @returns {string}\n */\nlet f = function(n) { return n; };";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		// find the variable_declarator value (function_expression)
		let stmt = ts.namedChild(root, 1);  // lexical_declaration (after comment)
		let decl = ts.namedChild(stmt, 0);
		let fnNode = ts.childByField(decl, 'value');

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, ts.startByte(fnNode));
		let t = inferNode(fnNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});
});

describe('inferrer — builtins', () => {
	it('length is in scope with nullable int return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let t = scopeGet(scope, 'length');
		assert.match(true, t !== null);
		assert.match('function', t.kind);
		assert.match({ kind: 'nullable', inner: prim('int') }, t.return);
	});

	it('sprintf is in scope with string return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let t = scopeGet(scope, 'sprintf');
		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});

	it('keys is in scope with nullable list<string> return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let t = scopeGet(scope, 'keys');
		assert.match('function', t.kind);
		assert.match({ kind: 'nullable', inner: { kind: 'generic', base: 'list', params: [{ kind: 'primitive', name: 'string' }] } }, t.return);
	});

	it('builtins do not pollute scope.bindings — they live in the parent chain', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		// scopeGet finds builtins through the parent chain
		assert.match(true, scopeGet(scope, 'push') !== null);
		// but the immediate frame is empty (no local declarations)
		assert.match(null, scope.bindings['push'] ?? null);
	});
});

describe('inferrer — buildScope: local function declarations', () => {
	it('function_declaration inside a function body is in scope', () => {
		let text = "function outer() {\nfunction helper(x) { return 1; }\nhelper;\n}";
		let tree = parse(text);
		let offset = length("function outer() {\nfunction helper(x) { return 1; }\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'helper');
		assert.match(true, t !== null);
		assert.match('function', t.kind);
	});

	it('top-level function_declaration is in scope', () => {
		let text = "function greet() { return 'hi'; }\ngreet;\n";
		let tree = parse(text);
		let offset = length(text) - 1;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'greet');
		assert.match(true, t !== null);
		assert.match('function', t.kind);
	});
});

describe('inferrer — buildScope: local declarations inside function bodies', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	it('let inside a function body is in scope', () => {
		let text = "function f() {\nlet x = 42;\nx;\n}";
		let tree = parse(text);
		// Offset at 'x' reference (inside body, after the let)
		let offset = length("function f() {\nlet x = 42;\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'x'));
	});

	it('local var gets return type of a namespace member call', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nfunction f(p) {\nlet root = ts.rootNode(p);\nroot;\n}";
		let tree = parse(text);
		// Offset at 'root' reference inside body
		let offset = length("import * as ts from 'tree_sitter';\nfunction f(p) {\nlet root = ts.rootNode(p);\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'root');
		assert.match(true, t !== null && t.kind !== 'unknown');
		// rootNode returns Node (ref type)
		assert.match('ref', t.kind);
		assert.match('Node', t.name);
	});

	it('let declared after cursor is not in scope', () => {
		let text = "function f() {\nlet x = 1;\nlet y = 2;\n}";
		let tree = parse(text);
		// Offset between x and y declarations
		let offset = length("function f() {\nlet x = 1;\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'x'));
		assert.match(null, scopeGet(scope, 'y'));
	});
});

describe('inferrer — union type member access', () => {
	it('member access on union type returns union of member types', () => {
		let s = makeScope(null);
		// x: { val: int } | { val: string }
		scopeSet(s, 'x', {
			kind: 'union',
			members: [
				{ kind: 'record', fields: [{ name: 'val', type: prim('int') }] },
				{ kind: 'record', fields: [{ name: 'val', type: prim('string') }] },
			]
		});
		let text = "let r = x.val;";
		let tree = parse(text);
		let expr = ts.childByField(ts.namedChild(ts.namedChild(ts.rootNode(tree), 0), 0), 'value');
		dag.add(URI, text, tree);
		let t = inferNode(expr, text, URI, s, 0);
		assert.match('union', t.kind);
		assert.match(2, length(t.members));
	});

	it('member access on union where all members agree returns plain type', () => {
		let s = makeScope(null);
		scopeSet(s, 'x', {
			kind: 'union',
			members: [
				{ kind: 'record', fields: [{ name: 'val', type: prim('int') }] },
				{ kind: 'record', fields: [{ name: 'val', type: prim('int') }] },
			]
		});
		let text = "let r = x.val;";
		let tree = parse(text);
		let expr = ts.childByField(ts.namedChild(ts.namedChild(ts.rootNode(tree), 0), 0), 'value');
		dag.add(URI, text, tree);
		let t = inferNode(expr, text, URI, s, 0);
		assert.match(prim('int'), t);
	});
});

describe('inferrer — _collectReturns tracks local let bindings', () => {
	it('return type resolved via let declared inside a branch', () => {
		let text = "function f(x) { if (x) { let r = 42; return r; } return null; }";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let fnNode = ts.namedChild(root, 0);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);
		let t = inferNode(fnNode, text, URI, scope, 0);
		assert.match('function', t.kind);
		assert.match('union', t.return.kind);
		// Should be int | null (not unknown | null)
		let kinds = map(t.return.members, (m) => m.kind + (m.name ? ':' + m.name : ''));
		assert.match(true, index(kinds, 'primitive:int') >= 0);
	});

	it('local let does not leak into outer scope', () => {
		let text = "function f() {\nlet x = 1;\nlet y = 2;\n}";
		let tree = parse(text);
		let offset = length("function f() {\nlet x = 1;\n");
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);
		assert.match(prim('int'), scopeGet(scope, 'x'));
		assert.match(null, scopeGet(scope, 'y'));
	});
});

describe('inferrer — chained member access', () => {
	it('a.b.c resolves when a.b is a record with field c', () => {
		let s = makeScope(null);
		// a has type { b: { c: int } }
		scopeSet(s, 'a', {
			kind: 'record',
			fields: [{ name: 'b', type: { kind: 'record', fields: [{ name: 'c', type: prim('int') }] } }]
		});
		// parse `let x = a.b.c;` and infer the member_expression a.b.c
		let text = "let x = a.b.c;";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let decl = ts.namedChild(root, 0);
		let vd   = ts.namedChild(decl, 0);
		let expr = ts.childByField(vd, 'value');  // member_expression a.b.c

		dag.add(URI, text, tree);
		let t = inferNode(expr, text, URI, s, 0);
		assert.match(prim('int'), t);
	});

	it('a.b where a is a record returns the field type', () => {
		let s = makeScope(null);
		scopeSet(s, 'obj', { kind: 'record', fields: [{ name: 'x', type: prim('string') }] });
		let text = "let r = obj.x;";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let expr = ts.childByField(ts.namedChild(ts.namedChild(root, 0), 0), 'value');

		dag.add(URI, text, tree);
		let t = inferNode(expr, text, URI, s, 0);
		assert.match(prim('string'), t);
	});
});

describe('inferrer — property_identifier in member expression', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	it('inferring a property_identifier redirects to its member_expression', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts.text;\n";
		let tree = parse(text);

		// Find the property_identifier node for 'text'
		let root = ts.rootNode(tree);
		let exprStmt = ts.namedChild(root, 1);
		let memberExpr = ts.namedChild(exprStmt, 0);
		let propNode = ts.namedChild(memberExpr, 1);  // property_identifier

		assert.match('property_identifier', ts.nodeType(propNode));

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, ts.startByte(propNode));
		let t = inferNode(propNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});
});

describe('inferrer — buildScope: callback parameter types from call context', () => {
	it('function_expression callback param typed from callee signature (type var resolved)', () => {
		// filter(list<string>, function(x) {...}) → x should be string
		let text = "let items = ['a', 'b'];\nfilter(items, function(x) {\n    x;\n});";
		let tree = parse(text);
		let offset = index(text, '\n    x;') + 5;  // at standalone 'x' in callback body

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'x'));
	});

	it('arrow callback param typed from callee signature', () => {
		let text = "let items = ['a', 'b'];\nfilter(items, x => {\n    x;\n});";
		let tree = parse(text);
		let offset = index(text, '\n    x;') + 5;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('string'), scopeGet(scope, 'x'));
	});

	it('callback param type resolves T when callee is an outer function param', () => {
		// Outer function param 'arr' typed as list<int>; filter(arr, function(el) {...})
		// enclosing function param scope for 'arr' must be built before callback context
		let text = "/**\n * @param {list<int>} arr\n */\nfunction outer(arr) {\n    filter(arr, function(el) {\n        el;\n    });\n}";
		let tree = parse(text);
		let offset = index(text, '\n        el;') + 9;  // at 'el' in callback body

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(prim('int'), scopeGet(scope, 'el'));
	});
});

describe('inferrer — nullable type unwrapping', () => {
	it('member access on nullable ref unwraps and resolves the field', () => {
		// ?MyType.field should resolve to the field type, not UNKNOWN
		let text = "/** @typedef {{ value: number }} MyType */\nlet x = null;\nlet r = x.value;";
		// We can't easily test full typedef resolution here; test that ?record unwraps:
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'nullable', inner: { kind: 'record', fields: [{ name: 'v', type: prim('int') }] } });
		let tree = parse("x.v;");
		dag.add(URI, "x.v;", tree);
		let root = ts.rootNode(tree);
		let memberNode = ts.namedChild(root, 0);  // expression_statement
		memberNode = ts.namedChild(memberNode, 0); // member_expression
		let t = inferNode(memberNode, "x.v;", URI, scope, 0);
		assert.match(prim('int'), t);
	});

	it('for-in over nullable list<int> gives int loop variable', () => {
		let text = "let xs = null;\nfor (let x in xs) {\nx;\n}";
		let tree = parse(text);
		let offset = length("let xs = null;\nfor (let x in xs) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);
		// xs has no type info from null, so we verify the nullable unwrap path works
		// by providing the type directly in scope
		let scope2 = makeScope(null);
		scopeSet(scope2, 'xs', { kind: 'nullable', inner: { kind: 'generic', base: 'list', params: [prim('int')] } });
		// Rebuild with the injected scope context — test via addForInVar indirectly
		// by checking that a nullable list in buildScope gives the right elem type.
		// (buildScope re-infers, so we need a typed declaration)
		let text2 = "/**\n * @returns {?list<int>}\n */\nfunction getXs() {}\nfor (let x in getXs()) {\nx;\n}";
		let tree2 = parse(text2);
		let offset2 = length(text2) - length("x;\n}") - 1;
		dag.add(URI, text2, tree2);
		if (_globalUri) {
			let scope3 = scopeFor(text2, tree2, offset2);
			assert.match(prim('int'), scopeGet(scope3, 'x'));
		}
	});
});

describe('inferrer — multiple return statement union', () => {
	it('function with two returns unions both types', () => {
		let text = "function f(x) { if (x) return 1; return 'a'; }";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let fnNode = ts.namedChild(root, 0);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);
		let t = inferNode(fnNode, text, URI, scope, 0);
		assert.match('function', t.kind);
		assert.match('union', t.return.kind);
		assert.match(2, length(t.return.members));
	});

	it('function with one return keeps a plain type', () => {
		let text = "function f() { return 42; }";
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let fnNode = ts.namedChild(root, 0);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);
		let t = inferNode(fnNode, text, URI, scope, 0);
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});

	it('arrow with two returns unions both types', () => {
		let text = "let f = (x) => { if (x) return 1; return 'a'; };";
		let t = infer(text);
		assert.match('function', t.kind);
		assert.match('union', t.return.kind);
		assert.match(2, length(t.return.members));
	});
});

describe('inferrer — buildScope: C-style for loop variable', () => {
	it('C-style for loop counter is in scope inside the body', () => {
		let text = "for (let i = 0; i < 10; i++) {\ni;\n}";
		let tree = parse(text);
		let offset = length("for (let i = 0; i < 10; i++) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(true, scopeGet(scope, 'i') !== null);
		assert.match(prim('int'), scopeGet(scope, 'i'));
	});

	it('C-style for loop counter is not in scope after the for statement', () => {
		let text = "for (let i = 0; i < 10; i++) {}\ni;\n";
		let tree = parse(text);
		let offset = length(text) - 2;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(null, scopeGet(scope, 'i'));
	});
});

describe('inferrer — buildScope: catch clause variable', () => {
	it('catch parameter is in scope inside the catch body', () => {
		let text = "try { } catch (e) {\ne;\n}";
		let tree = parse(text);
		let offset = length("try { } catch (e) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(true, scopeGet(scope, 'e') !== null);
	});

	it('catch parameter is not in scope after the catch block', () => {
		let text = "try { } catch (e) {}\ne;\n";
		let tree = parse(text);
		let offset = length(text) - 2;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match(null, scopeGet(scope, 'e'));
	});
});

describe('inferrer — buildScope: Object/dict for-in key type', () => {
	it('for-in over Object<string, int> yields string keys', () => {
		// Object<K,V> normalises to {kind:'generic', base:'dict'} — for-in gives keys (string)
		let text2 = "/**\n * @returns {Object<string, int>}\n */\nfunction getMap() {}\nfor (let k in getMap()) {\nk;\n}";
		let tree2 = parse(text2);
		let offset2 = length(text2) - length("k;\n}") - 1;
		dag.add(URI, text2, tree2);
		if (_globalUri) {
			let scope = scopeFor(text2, tree2, offset2);
			assert.match(prim('string'), scopeGet(scope, 'k'));
		}
	});
});

describe('inferrer — export clause carries doc', () => {
	let GREET_URI = 'file:///app/test/fixtures/greet.uc';

	it('exported name via export { name } has the function kind', () => {
		dag.init({ workspaceDir: '/app', workspace: { libraryPaths: ['src', 'test'] } });
		dag.addFromDisk(GREET_URI);
		let exps = dag.exportsOf(GREET_URI);
		assert.match(true, exps !== null && length(exps) > 0);
		assert.match('greet', exps[0].name);
		assert.match('function', exps[0].kind);
	});
});

describe('inferrer — importScope: renamed imports', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI);
		invalidateUri(URI);
		dag.addFromDisk(TS_URI);
	});

	it('renamed import is available under its local binding name', () => {
		// import { parse as p } from 'tree_sitter'; → 'p' must be in scope, not 'parse'
		let text = "import { parse as p } from 'tree_sitter';\np;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;  // at 'p'
		let scope = scopeFor(text, tree, offset);
		assert.match(true, scopeGet(scope, 'p') !== null);
		assert.match(null, scopeGet(scope, 'parse'));
	});

	it('renamed import carries the resolved type from the source module', () => {
		let text = "import { parse as p } from 'tree_sitter';\np;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;
		let scope = scopeFor(text, tree, offset);
		// 'parse' is a function export — the renamed binding should have function kind
		assert.match('function', scopeGet(scope, 'p').kind);
	});

	it('unrenamed import is still available under its original name', () => {
		let text = "import { parse } from 'tree_sitter';\nparse;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;
		let scope = scopeFor(text, tree, offset);
		assert.match(true, scopeGet(scope, 'parse') !== null);
		assert.match('function', scopeGet(scope, 'parse').kind);
	});
});

describe('inferrer — require() module loader', () => {
	beforeEach(() => {
		dag.init({ workspaceDir: '/app', workspace: { libraryPaths: ['src', 'test'] } });
		dag.remove(URI);
		invalidateUri(URI);
	});

	it('require("spec") is typed as the module named by the specifier', () => {
		let t = infer('let m = require("fixtures.greet");');
		assert.match('module', t.kind);
		assert.match('fixtures.greet', t.path);
	});

	it('member access on a required module resolves to the export type', () => {
		// fixtures/greet.uc exports the function `greet`.
		let t = infer('let g = require("fixtures.greet").greet;');
		assert.match('function', t.kind);
	});

	it('member of a require-bound legacy (return-object) module resolves', () => {
		// fixtures/legacy_mod.uc exports via a top-level `return { greet, ... }`.
		let t = infer('let g = require("fixtures.legacy_mod").greet;');
		assert.match('function', t.kind);
	});

	it('a locally shadowed require is not treated as the module loader', () => {
		let text = 'let m = require("fixtures.greet");';
		// A real shadow lives in a non-root scope; the builtin sits in the root.
		let scope = makeScope(makeScope(null));
		scopeSet(scope, 'require', prim('string'));   // shadow the builtin
		let t = inferNode(exprNode(text), text, URI, scope, 0);
		assert.match(true, t.kind !== 'module');
	});

	it('require with a non-literal specifier is not a module type', () => {
		let t = infer('let m = require(dynamicName);');
		assert.match(true, t.kind !== 'module');
	});
});

describe('inferrer — importScope: object-literal export typed as record', () => {
	let MY_URI = 'file:///app/src/mymod.uc';
	// Uses explicit pair syntax (greet: greet) to avoid shorthand property nodes.
	let modContent = "/** @param {string} s @returns {int} */\nfunction greet(s) { return 0; }\nexport const ns = { greet: greet };";

	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI);
		dag.remove(MY_URI);
		invalidateUri(URI);
	});

	it('imported object-literal const is typed as a record with correct fields', () => {
		mock.global.patch('fs', {
			data: { '/app/src/mymod.uc': modContent },
			behavior: { stat: (path) => (path === '/app/src/mymod.uc') ? { type: 'file', size: length(modContent) } : null }
		});
		dag.add(MY_URI, modContent, parse(modContent));
		let importText = "import { ns } from 'mymod';\nns;";
		let tree = parse(importText);
		dag.add(URI, importText, tree);
		let scope = scopeFor(importText, tree, length(importText) - 1);
		mock.global.unpatch('fs');
		let ns = scopeGet(scope, 'ns');
		assert.match('record', ns.kind);
		assert.match('greet', ns.fields[0].name);
		assert.match('function', ns.fields[0].type.kind);
	});
});

describe('inferrer — member access on record-typed expression (nested object export)', () => {
	let MOD_URI = 'file:///app/src/nested.uc';

	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI);
		dag.remove(MOD_URI);
		invalidateUri(URI);
	});

	it('resolves member of a nested object export to function type', () => {
		// export const api = { sub: { /** @returns {int} */ go: function() {} } };
		// Importing { api } and accessing api.sub.go must yield a function type.
		let modText = "export const api = { sub: { /** @returns {int} */ go: function() {} } };";
		dag.add(MOD_URI, modText, parse(modText));
		mock.global.patch('fs', {
			data: { '/app/src/nested.uc': modText },
			behavior: { stat: (path) => (path === '/app/src/nested.uc') ? { type: 'file', size: length(modText) } : null }
		});
		let text = "import { api } from 'nested';\napi.sub.go;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;
		let scope = scopeFor(text, tree, offset);
		mock.global.unpatch('fs');

		// api → record; api.sub → record; api.sub.go → function
		let api = scopeGet(scope, 'api');
		assert.match('record', api.kind);
		let subField = api.fields[0];
		assert.match('sub', subField.name);
		assert.match('record', subField.type.kind);
		let goField = subField.type.fields[0];
		assert.match('go', goField.name);
		assert.match('function', goField.type.kind);
	});

	it('record field carries doc for hover lookup', () => {
		let modText = "export const api = { /** @param {string} s @returns {int} */ greet: function(s) {} };";
		dag.add(MOD_URI, modText, parse(modText));
		mock.global.patch('fs', {
			data: { '/app/src/nested.uc': modText },
			behavior: { stat: (path) => (path === '/app/src/nested.uc') ? { type: 'file', size: length(modText) } : null }
		});
		let text = "import { api } from 'nested';\napi.greet;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, length(text) - 1);
		mock.global.unpatch('fs');

		let field = scopeGet(scope, 'api').fields[0];
		assert.match('greet', field.name);
		assert.match(true, field.doc !== null);
		assert.match('s', field.doc.params[0].name);
	});
});

describe('inferrer — member access on module-typed expression', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	// Return the property_identifier node from `x.member;` expression text.
	function moduleMemberNode(text) {
		let tree  = parse(text);
		let root  = ts.rootNode(tree);
		let stmt  = ts.namedChild(root, 0);   // expression_statement
		let mexpr = ts.namedChild(stmt, 0);   // member_expression
		return ts.namedChild(mexpr, 1);
	}

	it('resolves member of a module-typed binding when module is pre-indexed', () => {
		dag.addFromDisk(TS_URI);
		let propNode = moduleMemberNode('x.parse;');
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'module', path: 'tree_sitter' });
		let type = inferNode(propNode, 'x.parse;', URI, scope, 0);
		assert.match('function', type.kind);
	});

	it('lazy-indexes the module from disk when not yet in the DAG', () => {
		// tree_sitter is NOT pre-indexed — the inferrer must call addFromDisk itself.
		dag.remove(TS_URI);
		let propNode = moduleMemberNode('x.parse;');
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'module', path: 'tree_sitter' });
		let type = inferNode(propNode, 'x.parse;', URI, scope, 0);
		assert.match('function', type.kind);
	});
});

describe('inferrer — subscript_expression (array/object indexing)', () => {
	it('arr[i] returns the list element type', () => {
		let t = infer("let x = [1, 2, 3][0];");
		// [1,2,3] is list<int>; [0] extracts the element
		assert.match('primitive', t.kind);
		assert.match('int', t.name);
	});

	it('arr[i] on a typed binding returns the element type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'items', { kind: 'generic', base: 'list', params: [{ kind: 'primitive', name: 'string' }] });
		let node = exprNode("let x = items[0];");
		let t = inferNode(node, "let x = items[0];", URI, scope, 0);
		assert.match('primitive', t.kind);
		assert.match('string', t.name);
	});

	it('obj["key"] returns the record field type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'obj', {
			kind: 'record',
			fields: [{ name: 'count', type: { kind: 'primitive', name: 'int' } }],
			sourceUri: URI,
		});
		let node = exprNode('let x = obj["count"];');
		let t = inferNode(node, 'let x = obj["count"];', URI, scope, 0);
		assert.match('primitive', t.kind);
		assert.match('int', t.name);
	});

	it('obj["missing"] returns unknown for absent field', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'obj', { kind: 'record', fields: [], sourceUri: URI });
		let node = exprNode('let x = obj["missing"];');
		let t = inferNode(node, 'let x = obj["missing"];', URI, scope, 0);
		assert.match('unknown', t.kind);
	});

	it('arr?.[i] returns a nullable element type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'arr', { kind: 'generic', base: 'list', params: [{ kind: 'primitive', name: 'string' }] });
		let text = "let x = arr?.[0];";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		assert.match('nullable', t.kind);
		assert.match('string', t.inner.name);
	});
});

describe('inferrer — optional chaining on member_expression', () => {
	it('a?.b returns a nullable version of the member type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'obj', {
			kind: 'record',
			fields: [{ name: 'name', type: { kind: 'primitive', name: 'string' } }],
			sourceUri: URI,
		});
		let text = "let x = obj?.name;";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		assert.match('nullable', t.kind);
		assert.match('string', t.inner.name);
	});

	it('non-optional member returns non-nullable type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'obj', {
			kind: 'record',
			fields: [{ name: 'count', type: { kind: 'primitive', name: 'int' } }],
			sourceUri: URI,
		});
		let text = "let x = obj.count;";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		assert.match('primitive', t.kind);
		assert.match('int', t.name);
	});
});

describe('inferrer — spread_element', () => {
	it('spread of list<T> in array literal contributes T as element type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'items', { kind: 'generic', base: 'list', params: [{ kind: 'primitive', name: 'string' }] });
		let text = "let x = [...items];";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		// [...list<string>] → list<string>
		assert.match('generic', t.kind);
		assert.match('list', t.base);
		assert.match('string', t.params[0].name);
	});

	it('spread of record in object literal merges fields', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'base', {
			kind: 'record',
			fields: [{ name: 'x', type: { kind: 'primitive', name: 'int' } }],
			sourceUri: URI,
		});
		let text = "let y = { ...base, z: 'hello' };";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		assert.match('record', t.kind);
		let names = sort(map(t.fields, (f) => f.name));
		// x comes from spread, z from the pair
		assert.match(true, index(names, 'x') >= 0);
		assert.match(true, index(names, 'z') >= 0);
	});
});

describe('inferrer — shorthand_property_identifier', () => {
	it('{ x } shorthand resolves x from scope', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'count', { kind: 'primitive', name: 'int' });
		let text = "let y = { count };";
		let node = exprNode(text);
		let t = inferNode(node, text, URI, scope, 0);
		assert.match('record', t.kind);
		assert.match(1, length(t.fields));
		assert.match('count', t.fields[0].name);
		assert.match('int', t.fields[0].type.name);
	});
});

describe('inferrer — binary_expression &&/||', () => {
	it('|| returns union of operand types', () => {
		let t = infer("let x = 1 || 'hello';");
		assert.match('union', t.kind);
		let names = sort(map(t.members, (m) => m.name));
		assert.match(true, index(names, 'int') >= 0);
		assert.match(true, index(names, 'string') >= 0);
	});

	it('&& of same type returns that type', () => {
		let t = infer("let x = 1 && 2;");
		assert.match('primitive', t.kind);
		assert.match('int', t.name);
	});

	it('comparison operators still return bool', () => {
		assert.match('boolean', infer("let x = 1 < 2;").name);
		assert.match('boolean', infer("let x = 1 === 2;").name);
	});
});

describe('inferrer — unary delete', () => {
	it('delete returns boolean', () => {
		let t = infer("let x = delete obj;");
		assert.match('primitive', t.kind);
		assert.match('boolean', t.name);
	});

	it('! still returns boolean', () => {
		assert.match('boolean', infer("let x = !someVar;").name);
	});
});

describe('inferrer — rest params', () => {
	function inferFn(text) {
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let fn = ts.namedChild(root, 0);
		return inferNode(fn, text, URI, makeScope(null), 0);
	}

	it('function_declaration: rest param appears in inferred type params', () => {
		let t = inferFn("function f(...args) { return args; }");
		assert.match('function', t.kind);
		let names = map(t.params, (p) => p.name);
		assert.match(true, index(names, 'args') >= 0);
	});

	it('function_declaration: rest param has list type', () => {
		let t = inferFn("function f(...args) { return args; }");
		let p = null;
		for (let i in t.params) if (i.name === 'args') { p = i; break; }
		if (p === null) die('expected a rest param named args');
		assert.match('generic', p.type.kind);
		assert.match('list', p.type.base);
	});

	it('function_declaration: plain and rest params both present', () => {
		let t = inferFn("function f(a, ...rest) { return rest; }");
		assert.match('function', t.kind);
		let names = map(t.params, (p) => p.name);
		assert.match(true, index(names, 'a') >= 0);
		assert.match(true, index(names, 'rest') >= 0);
	});

	it('arrow function: rest param appears in inferred type params', () => {
		let t = infer("let f = (...args) => args;");
		assert.match('function', t.kind);
		let names = map(t.params, (p) => p.name);
		assert.match(true, index(names, 'args') >= 0);
	});

	it('rest param is in scope inside function body', () => {
		let text = "function f(...args) { return args; }";
		// position inside the body (after the '{')
		let bodyOffset = index(text, 'return');
		let scope = scopeFor(text, parse(text), bodyOffset);
		let t = scopeGet(scope, 'args');
		assert.match(true, t !== null);
		assert.match('generic', t.kind);
		assert.match('list', t.base);
	});
});

describe('inferrer — object with string-literal keys', () => {
	it('"key": value is indexed as a record field', () => {
		let t = infer('let x = { "host": "localhost", "port": 8080 };');
		assert.match('record', t.kind);
		let names = sort(map(t.fields, (f) => f.name));
		assert.match(true, index(names, 'host') >= 0);
		assert.match(true, index(names, 'port') >= 0);
	});

	it('string-keyed field has the correct inferred value type', () => {
		let t = infer('let x = { "count": 42 };');
		assert.match('record', t.kind);
		assert.match(1, length(t.fields));
		assert.match('count', t.fields[0].name);
		assert.match('int', t.fields[0].type.name);
	});
});

describe('inferrer — scope-ID cache isolation', () => {
	// The same AST node inferred under two different scope objects must produce
	// independent results; the second inference must not return the first's
	// cached value just because the node is at the same byte offset.

	it('same identifier node with two different scope bindings returns scope-specific type', () => {
		// 'let y = x;' — the 'x' node on the right is the subject.
		let text = 'let y = x;';
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let stmt = ts.namedChild(root, 0);   // lexical_declaration
		let decl = ts.namedChild(stmt, 0);   // variable_declarator
		let xNode = ts.childByField(decl, 'value');  // 'x' identifier

		let s1 = makeScope(null);
		scopeSet(s1, 'x', prim('int'));

		let s2 = makeScope(null);
		scopeSet(s2, 'x', prim('string'));

		// Infer with s1 first so the result is cached under s1.id.
		assert.match(prim('int'), inferNode(xNode, text, URI, s1, 0));

		// Infer with s2: must NOT return the s1 cached value.
		assert.match(prim('string'), inferNode(xNode, text, URI, s2, 0));
	});

	it('same identifier node inferred twice with the same scope returns cached result', () => {
		let text = 'let y = x;';
		let tree = parse(text);
		let root = ts.rootNode(tree);
		let stmt = ts.namedChild(root, 0);
		let decl = ts.namedChild(stmt, 0);
		let xNode = ts.childByField(decl, 'value');

		let s = makeScope(null);
		scopeSet(s, 'x', prim('bool'));

		assert.match(prim('bool'), inferNode(xNode, text, URI, s, 0));
		assert.match(prim('bool'), inferNode(xNode, text, URI, s, 0));
	});
});

describe('inferrer — buildScope flow sensitivity', () => {
	// buildScope narrows identifier types inside if-consequent/alternate blocks
	// based on the condition pattern.  We use `42 || null` as the initializer
	// because the inferrer produces union[int, null] for that expression.

	function scopeAt(text, offset) {
		let tree = parse(text);
		dag.add(URI, text, tree);
		return scopeFor(text, tree, offset);
	}

	it('x !== null in consequent: removes null from union type', () => {
		// let x = 42 || null;  → union[int, null]
		// if (x !== null) { x; }  ← offset inside block
		let text = "let x = 42 || null;\nif (x !== null) {\n  x;\n}\n";
		let offset = index(text, '  x;');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('int', t.name ?? t.kind);
	});

	it('x !== null in alternate: narrows to null', () => {
		let text = "let x = 42 || null;\nif (x !== null) {\n  x;\n} else {\n  x;\n}\n";
		let offset = index(text, '} else {\n  x;') + length('} else {\n  ');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('null', t.name);
	});

	it('x === null in consequent: narrows to null', () => {
		let text = "let x = 42 || null;\nif (x === null) {\n  x;\n}\n";
		let offset = index(text, '  x;');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('null', t.name);
	});

	it('if (x) truthy check in consequent: removes null from union type', () => {
		let text = "let x = 42 || null;\nif (x) {\n  x;\n}\n";
		let offset = index(text, '  x;');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('int', t.name ?? t.kind);
	});

	it('!x in consequent: narrows to null (was unhandled before narrowing unification)', () => {
		let text = "let x = 42 || null;\nif (!x) {\n  x;\n}\n";
		let offset = index(text, '  x;');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('null', t.name);
	});

	it('!x in alternate: removes null (guard-clause equivalent)', () => {
		let text = "let x = 42 || null;\nif (!x) {\n  x;\n} else {\n  x;\n}\n";
		let offset = index(text, '} else {\n  x;') + length('} else {\n  ');
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		assert.match('int', t.name ?? t.kind);
	});

	it('no narrowing outside the if block', () => {
		let text = "let x = 42 || null;\nif (x !== null) {\n  x;\n}\nx;\n";
		let offset = length(text) - length('x;\n') + 0;
		let scope = scopeAt(text, offset);
		let t = scopeGet(scope, 'x');
		// Outside the if block, type is still the original union
		assert.match('union', t.kind);
	});
});

