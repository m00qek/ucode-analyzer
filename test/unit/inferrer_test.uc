import { describe, it, assert, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag';
import { inferNode, buildScope } from 'ucode_language_server.inferrer';
import { makeScope, scopeSet, scopeGet } from 'ucode_language_server.scope';
import { invalidateUri } from 'ucode_language_server.memo';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

let URI = 'file:///app/src/test_main.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

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

	it('arithmetic on float yields float', () => {
		assert.match(prim('float'), infer('let x = 1.5 * 2;'));
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
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['a']);
		assert.match(prim('string'), scope.bindings['b']);
		assert.match(null, scope.bindings['c']);
	});

	it('includes function parameters for an offset inside a function body', () => {
		// Offset inside the body: after the opening brace, before the return.
		// 'x' is a parameter; it should appear in scope with unknown type (no JSDoc).
		let text = "function add(x, y) {\nreturn x + y;\n}";
		let tree = parse(text);
		// Position of 'x' reference on line 1 (inside the body)
		let offset = length("function add(x, y) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		// Parameters must be in scope (even without JSDoc the bindings key exists)
		assert.match(true, 'x' in scope.bindings);
		assert.match(true, 'y' in scope.bindings);
	});

	it('uses JSDoc @param types when present', () => {
		let text = "/** @param {int} n — count */\nfunction double(n) {\nreturn n * 2;\n}";
		let tree = parse(text);
		let offset = length("/** @param {int} n — count */\nfunction double(n) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['n']);
	});

	it('single-param arrow parameter is in scope inside the body', () => {
		let text = "let f = x => x + 1;";
		let tree = parse(text);
		// Offset inside the arrow body (at `x` in `x + 1`)
		let offset = length("let f = x => ");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(true, 'x' in scope.bindings);
	});

	it('inner parameters shadow outer ones of the same name', () => {
		let text = "function outer(x) {\nfunction inner(x) {\nreturn x;\n}\n}";
		let tree = parse(text);
		// Offset inside inner(): after 'return '
		let offset = length("function outer(x) {\nfunction inner(x) {\nreturn ");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		// The binding for 'x' should exist (the inner one wins — same key, last write wins)
		assert.match(true, 'x' in scope.bindings);
	});
});

describe('inferrer — buildScope: export let', () => {
	it('export let declarations are in scope', () => {
		let text = "export let count = 42;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['count']);
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
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['ts'];
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
		let scope = buildScope(URI, text, tree, offset);

		assert.match(true, 'it' in scope.bindings);
		// items is list<int>, so element type is int
		assert.match(prim('int'), scope.bindings['it']);
	});

	it('loop variable over a record literal is string (key iteration)', () => {
		let text = "let m = { a: 1, b: 2 };\nfor (let k in m) {\nk;\n}";
		let tree = parse(text);
		let offset = length("let m = { a: 1, b: 2 };\nfor (let k in m) {\n");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('string'), scope.bindings['k']);
	});

	it('loop variable is not in scope after the for-in statement', () => {
		let text = "for (let k in [1]) {}\nk;\n";
		let tree = parse(text);
		let offset = length(text) - 2;  // at 'k' after the for

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(null, scope.bindings['k'] ?? null);
	});
});

describe('inferrer — buildScope: assignment expression', () => {
	it('updates a declared variable type on assignment', () => {
		// x starts as string (from the literal), then gets reassigned to int
		let text = "let x = 'hello';\nx = 42;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['x']);
	});

	it('does not create a new binding for undeclared identifiers', () => {
		let text = "undeclared = 5;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		assert.match(null, scope.bindings['undeclared'] ?? null);
	});
});

describe('inferrer — object literals', () => {
	it('infers a record type from an object literal', () => {
		let t = infer('let o = { a: 1, b: "hi" };');
		assert.match('record', t.kind);
		assert.match(2, length(t.fields));
		assert.match('a', t.fields[0].name);
		assert.match(prim('int'), t.fields[0].type);
		assert.match('b', t.fields[1].name);
		assert.match(prim('string'), t.fields[1].type);
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
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['inner'];
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});

	it('nested function_expression uses doc before its let, not the enclosing function doc', () => {
		let text = "/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\nf;\n}";
		let tree = parse(text);
		let offset = length("/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\n");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['f'];
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});
});

describe('inferrer — function_expression', () => {
	it('infers a function type from body', () => {
		let t = infer('let f = function(a) { return 1; };');
		assert.match('function', t.kind);
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
		let scope = buildScope(URI, text, tree, ts.startByte(fnNode));
		let t = inferNode(fnNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});
});

describe('inferrer — builtins', () => {
	it('length is in scope with int return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, 0);

		let t = scopeGet(scope, 'length');
		assert.match(true, t !== null);
		assert.match('function', t.kind);
		assert.match(prim('int'), t.return);
	});

	it('sprintf is in scope with string return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, 0);

		let t = scopeGet(scope, 'sprintf');
		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
	});

	it('keys is in scope with list<string> return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, 0);

		let t = scopeGet(scope, 'keys');
		assert.match('function', t.kind);
		assert.match({ kind: 'generic', base: 'list', params: [prim('string')] }, t.return);
	});

	it('builtins do not pollute scope.bindings — they live in the parent chain', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, 0);

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
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['helper'];
		assert.match(true, t !== null);
		assert.match('function', t.kind);
	});

	it('top-level function_declaration is in scope', () => {
		let text = "function greet() { return 'hi'; }\ngreet;\n";
		let tree = parse(text);
		let offset = length(text) - 1;

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['greet'];
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
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['x']);
	});

	it('local var gets return type of a namespace member call', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nfunction f(p) {\nlet root = ts.rootNode(p);\nroot;\n}";
		let tree = parse(text);
		// Offset at 'root' reference inside body
		let offset = length("import * as ts from 'tree_sitter';\nfunction f(p) {\nlet root = ts.rootNode(p);\n");

		dag.add(URI, text, tree);
		let scope = buildScope(URI, text, tree, offset);

		let t = scope.bindings['root'];
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
		let scope = buildScope(URI, text, tree, offset);

		assert.match(prim('int'), scope.bindings['x']);
		assert.match(null, scope.bindings['y'] ?? null);
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
		let scope = buildScope(URI, text, tree, ts.startByte(propNode));
		let t = inferNode(propNode, text, URI, scope, 0);

		assert.match('function', t.kind);
		assert.match(prim('string'), t.return);
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
