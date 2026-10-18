import { describe, it, assert, mock, beforeEach, prop, gen } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { returnOf } from 'ucode_analyzer.code_analysis.types.unifier';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { buildScopeMap, scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { makeScope, scopeSet, scopeGet } from 'ucode_analyzer.code_analysis.types.scope';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

let URI = fixture.uri('test_main.uc');
let PARSER_URI = fixture.uri('parser.uc');

let _config = fixture.config();

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

	it('infers exponent literal as float', () => {
		assert.match(prim('float'), infer('let x = 1e5;'));
	});

	it('infers uppercase-exponent literal as float', () => {
		assert.match(prim('float'), infer('let x = 1E5;'));
	});

	it('infers hex literal with an e digit as int (not float)', () => {
		assert.match(prim('int'), infer('let x = 0x1e;'));
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

	it('?? unions the non-null left with the right', () => {
		// `1 ?? 'a'` → int | string (left is never null here, but the type union
		// is what a nullable left would collapse to).
		assert.match(union_(prim('int'), prim('string')), infer("let x = 1 ?? 'a';"));
	});

	it('?? with same-typed branches yields that type', () => {
		assert.match(prim('int'), infer('let x = 1 ?? 2;'));
	});
});

describe('inferrer — unary expressions', () => {
	it('! yields boolean', () => {
		assert.match(prim('boolean'), infer('let x = !true;'));
	});

	it('unary minus on int yields int', () => {
		assert.match(prim('int'), infer('let x = -1;'));
	});

	it('unary minus on float yields float', () => {
		assert.match(prim('float'), infer('let x = -1.5;'));
	});

	it('bitwise complement yields int', () => {
		assert.match(prim('int'), infer('let x = ~5;'));
	});

	it('unary plus on a string operand is numeric, not string', () => {
		// +"5" is an int at runtime; the inferrer must not report the operand's
		// string type. int-vs-float is undetermined, so it stays unknown.
		assert.match(unknown(), infer("let x = +'5';"));
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
		assert.match(list_(union_(prim('int'), prim('string'))), infer("let x = [1, 'a'];"));
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
		assert.match(prim('int'), returnOf(t));
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
		assert.match(prim('string'), returnOf(t));
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
		assert.match(prim('int'), returnOf(result));
		assert.match(1, length(result.params));
		assert.match('x', result.params[0].name);
	});

	it('multi-param arrow has correct param names and inferred return', () => {
		let result = infer('let f = (a, b) => true;');
		assert.match('function', result.kind);
		assert.match(prim('boolean'), returnOf(result));
		assert.match(2, length(result.params));
		assert.match('a', result.params[0].name);
		assert.match('b', result.params[1].name);
	});

	it('arrow body referring to unknown param yields unknown return', () => {
		// No pushed-down type context → param type is unknown → body `a` is unknown
		let result = infer('let f = a => a;');
		assert.match('function', result.kind);
		assert.match(unknown(), returnOf(result));
	});

	it('arrow with literal body ignores param type', () => {
		let result = infer("let f = x => 'hi';");
		assert.match('function', result.kind);
		assert.match(prim('string'), returnOf(result));
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

		// Parameters are in scope; without JSDoc their type is unknown.
		assert.match(unknown(), scopeGet(scope, 'x'));
		assert.match(unknown(), scopeGet(scope, 'y'));
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

		assert.match(unknown(), scopeGet(scope, 'x'));
	});

	it('inner parameters shadow outer ones of the same name', () => {
		let src = cursors("/** @param {int} x */\nfunction outer(x) {\n/** @param {string} x */\nfunction inner(x) {\nreturn $0x;\n}\n}");
		let tree = parse(src.text);

		dag.add(URI, src.text, tree);
		let scope = scopeFor(src.text, tree, src.offset[0]);

		assert.match(prim('string'), scopeGet(scope, 'x'));
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
		let text = "/**\n * @returns {string}\n */\nexport function tag(x) {};\nexport function caller(v) {\n    let r = tag(v);\n    r;\n};\n";
		let tree = parse(text);
		// offset at 'r;' inside caller
		let offset = index(text, '\n    r;') + 5;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match({ kind: 'function', params: [{ name: 'x', type: unknown() }], return: prim('string') }, scopeGet(scope, 'tag'));
		assert.match(prim('string'), scopeGet(scope, 'r'));
	});
});

describe('inferrer — buildScope: namespace import alias', () => {
	it('namespace alias is in scope as module type', () => {
		dag.addFromDisk(PARSER_URI);
		let text = "import * as ts from 'parser';\nts;\n";
		let tree = parse(text);
		let offset = length(text);

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		assert.match({ kind: 'module', path: 'parser' }, scopeGet(scope, 'ts'));
	});

	it('a local binding shadows a same-named namespace import in member access', () => {
		dag.addFromDisk(PARSER_URI);
		// `parser` is both a namespace import and a block-local record with a `parse`
		// field. Inside the block, `parser.parse` must resolve to the local record's
		// int field, not the parser module's parse() function.
		let text = "import * as parser from 'parser';\n{\nlet parser = { parse: 42 };\nlet r = parser.parse;\n}\n";
		let tree = parse(text);
		dag.add(URI, text, tree);

		let root  = ts.rootNode(tree);
		let block = ts.namedChild(root, 1);        // statement_block
		let rDecl = ts.namedChild(block, 1);       // `let r = parser.parse;`
		let declr = ts.namedChild(rDecl, 0);       // variable_declarator
		let member = ts.childByField(declr, 'value');  // parser.parse

		let scope = scopeFor(text, tree, ts.startByte(member));
		let t = inferNode(member, text, URI, scope, 0);
		// The local record's `parse` field is a literal int (carries value:42),
		// not the parser module's parse() function.
		assert.match('primitive', t.kind);
		assert.match('int', t.name);
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
		assert.match(prim('int'), returnOf(t));
	});

	it('nested function_expression uses doc before its let, not the enclosing function doc', () => {
		let text = "/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\nf;\n}";
		let tree = parse(text);
		let offset = length("/** @returns {string} */\nfunction outer() {\n/** @returns {int} */\nlet f = function() { return 1; };\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'f');
		assert.match('function', t.kind);
		assert.match(prim('int'), returnOf(t));
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
		assert.match(prim('string'), returnOf(t));
	});
});

describe('inferrer — builtins', () => {
	it('length is in scope with nullable int return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let collection = { kind: 'union', members: [
			{ kind: 'generic', base: 'dict', params: [unknown()] }, list_(unknown()), prim('string'),
		] };
		assert.match({
			kind: 'function',
			params: [{ name: 'x', type: collection }],
			return: { kind: 'nullable', inner: prim('int') },
		}, scopeGet(scope, 'length'));
	});

	it('sprintf is in scope with string return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let t = scopeGet(scope, 'sprintf');
		assert.match('function', t.kind);
		assert.match(prim('string'), returnOf(t));
	});

	it('keys is in scope with nullable list<string> return type', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		let t = scopeGet(scope, 'keys');
		assert.match('function', t.kind);
		assert.match({ kind: 'nullable', inner: { kind: 'generic', base: 'list', params: [{ kind: 'primitive', name: 'string' }] } }, returnOf(t));
	});

	it('builtins do not pollute scope.bindings — they live in the parent chain', () => {
		let text = "";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, 0);

		// scopeGet finds builtins through the parent chain
		let T = { kind: 'param', name: 'T' };
		assert.match({
			kind: 'function',
			params: [{ name: 'arr', type: list_(T) }, { name: 'values', type: T }],
			return: { kind: 'nullable', inner: T },
		}, scopeGet(scope, 'push'));
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
		assert.match('function', t.kind);
		assert.match([{ name: 'x', type: unknown() }], t.params);
		assert.match(prim('int'), returnOf(t));
	});

	it('top-level function_declaration is in scope', () => {
		let text = "function greet() { return 'hi'; }\ngreet;\n";
		let tree = parse(text);
		let offset = length(text) - 1;

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

		let t = scopeGet(scope, 'greet');
		assert.match('function', t.kind);
		assert.match([], t.params);
		assert.match(prim('string'), returnOf(t));
	});
});

describe('inferrer — buildScope: local declarations inside function bodies', () => {
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
		dag.addFromDisk(PARSER_URI);
		let src = cursors("import * as ts from 'parser';\nfunction f(n, s) {\nlet str = ts.text(n, s);\n$0str;\n}");
		let tree = parse(src.text);

		dag.add(URI, src.text, tree);
		let scope = scopeFor(src.text, tree, src.offset[0]);

		// text() is documented @returns {string}
		assert.match(prim('string'), scopeGet(scope, 'str'));
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
		assert.match(union_(prim('int'), prim('string')), inferNode(expr, text, URI, s, 0));
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
		// int | null, not unknown | null
		assert.match(union_(prim('int'), prim('null')), returnOf(t));
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
	it('inferring a property_identifier redirects to its member_expression', () => {
		dag.addFromDisk(PARSER_URI);
		let text = "import * as ts from 'parser';\nts.text;\n";
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
		assert.match(prim('string'), returnOf(t));
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
		assert.match(union_(prim('int'), prim('string')), returnOf(t));
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
		assert.match(prim('int'), returnOf(t));
	});

	it('arrow with two returns unions both types', () => {
		let text = "let f = (x) => { if (x) return 1; return 'a'; };";
		let t = infer(text);
		assert.match('function', t.kind);
		assert.match(union_(prim('int'), prim('string')), returnOf(t));
	});
});

describe('inferrer — buildScope: C-style for loop variable', () => {
	it('C-style for loop counter is in scope inside the body', () => {
		let text = "for (let i = 0; i < 10; i++) {\ni;\n}";
		let tree = parse(text);
		let offset = length("for (let i = 0; i < 10; i++) {\n");

		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, offset);

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

		// The exception object { type, message, stacktrace }, which prints as its
		// message.
		assert.match([ 'type', 'message', 'stacktrace' ], map(scopeGet(scope, 'e').fields, (f) => f.name));
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
	let GREET_URI = fixture.uri('greet.uc');

	it('exported name via export { name } has the function kind', () => {
		dag.init(_config);
		dag.addFromDisk(GREET_URI);
		assert.match([{
			name: 'greet', kind: 'function', doc: null, params: [], valueType: null,
			position: { line: 0, character: 9 },
			local: 'greet',
		}], dag.exportsOf(GREET_URI));
	});
});

describe('inferrer — importScope: renamed imports', () => {
	// parser.uc: @param {object} parser, @param {string} source, @returns {object}
	let OBJECT = { kind: 'ref', name: 'object', params: [] };
	let PARSE_FN = {
		kind: 'function',
		params: [{ name: 'parser', type: OBJECT }, { name: 'source', type: prim('string') }],
		return: OBJECT,
	};

	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI);
		invalidateUri(URI);
		dag.addFromDisk(PARSER_URI);
	});

	it('renamed import is available under its local binding name', () => {
		// import { parse as p } from 'parser'; → 'p' must be in scope, not 'parse'
		let text = "import { parse as p } from 'parser';\np;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;  // at 'p'
		let scope = scopeFor(text, tree, offset);
		assert.match(PARSE_FN, scopeGet(scope, 'p'));
		assert.match(null, scopeGet(scope, 'parse'));
	});

	it('renamed import carries the resolved type from the source module', () => {
		let text = "import { parse as p } from 'parser';\np;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;
		let scope = scopeFor(text, tree, offset);
		// 'parse' is a function export — the renamed binding should have function kind
		assert.match('function', scopeGet(scope, 'p').kind);
	});

	it('unrenamed import is still available under its original name', () => {
		let text = "import { parse } from 'parser';\nparse;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let offset = length(text) - 1;
		let scope = scopeFor(text, tree, offset);
		assert.match(PARSE_FN, scopeGet(scope, 'parse'));
	});
});

describe('inferrer — require() module loader', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI);
		invalidateUri(URI);
	});

	it('require("spec") is typed as the module named by the specifier', () => {
		let t = infer('let m = require("greet");');
		assert.match('module', t.kind);
		assert.match('greet', t.path);
	});

	it('member access on a required module resolves to the export type', () => {
		// greet.uc exports the function `greet`.
		let t = infer('let g = require("greet").greet;');
		assert.match('function', t.kind);
	});

	it('member of a require-bound legacy (return-object) module resolves', () => {
		// legacy_mod.uc exports via a top-level `return { greet, ... }`.
		let t = infer('let g = require("legacy_mod").greet;');
		assert.match('function', t.kind);
	});

	it('a locally shadowed require is not treated as the module loader', () => {
		let text = 'let m = require("greet");';
		// A real shadow lives in a non-root scope; the builtin sits in the root.
		let scope = makeScope(makeScope(null));
		scopeSet(scope, 'require', prim('string'));   // shadow the builtin
		let t = inferNode(exprNode(text), text, URI, scope, 0);
		assert.match(unknown(), t);
	});

	it('require with a non-literal specifier is not a module type', () => {
		let t = infer('let m = require(dynamicName);');
		assert.match(unknown(), t);
	});

	// ── guard branches ──────────────────────────────────────────────────────
	it('a zero-argument require() is not a module type', () => {
		let t = infer('let m = require();');
		assert.match(unknown(), t);
	});

	it('an empty-string require("") is not a module type', () => {
		let t = infer('let m = require("");');
		assert.match(unknown(), t);
	});

	it('require of an unresolved specifier is still a module type (path preserved)', () => {
		let t = infer('let m = require("no.such.module.xyz");');
		assert.match('module', t.kind);
		assert.match('no.such.module.xyz', t.path);
	});

	it('member access on an unresolved required module is unknown, not a crash', () => {
		let t = infer('let g = require("no.such.module.xyz").whatever;');
		assert.match('unknown', t.kind);
	});

	// ── round-trip property ─────────────────────────────────────────────────
	// For any dotted specifier that survives as a single string_fragment, the
	// inferred module type must carry that exact specifier as its path.
	prop("require(\"S\") round-trips the specifier into module.path",
		gen.map(gen.array(gen.alphanumeric({ min_len: 1, max_len: 4 }), { min_len: 1, max_len: 4 }),
		        (segs) => join('.', segs)),
		(spec) => {
			let t = infer(sprintf('let m = require("%s");', spec));
			assert.match('module', t.kind);
			assert.match(spec, t.path);
		});
});

describe('inferrer — importScope: object-literal export typed as record', () => {
	let MY_URI = fixture.uri('mymod.uc');
	let MY_PATH = fixture.WORKSPACE + '/mymod.uc';
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
			data: { [MY_PATH]: modContent },
			behavior: { stat: (path) => (path === MY_PATH) ? { type: 'file', size: length(modContent) } : null }
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
	let MOD_URI = fixture.uri('nested.uc');
	let MOD_PATH = fixture.WORKSPACE + '/nested.uc';

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
			data: { [MOD_PATH]: modText },
			behavior: { stat: (path) => (path === MOD_PATH) ? { type: 'file', size: length(modText) } : null }
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
			data: { [MOD_PATH]: modText },
			behavior: { stat: (path) => (path === MOD_PATH) ? { type: 'file', size: length(modText) } : null }
		});
		let text = "import { api } from 'nested';\napi.greet;";
		let tree = parse(text);
		dag.add(URI, text, tree);
		let scope = scopeFor(text, tree, length(text) - 1);
		mock.global.unpatch('fs');

		let field = scopeGet(scope, 'api').fields[0];
		assert.match('greet', field.name);
		assert.match([{
			name: 's', type: prim('string'), optional: false, rest: false,
			description: null, nameStart: 20, nameEnd: 21,
		}], field.doc.params);
		assert.match({ type: prim('int'), description: null }, field.doc.returns);
	});
});

describe('inferrer — member access on module-typed expression', () => {
	// Return the property_identifier node from `x.member;` expression text.
	function moduleMemberNode(text) {
		let tree  = parse(text);
		let root  = ts.rootNode(tree);
		let stmt  = ts.namedChild(root, 0);   // expression_statement
		let mexpr = ts.namedChild(stmt, 0);   // member_expression
		return ts.namedChild(mexpr, 1);
	}

	it('resolves member of a module-typed binding when module is pre-indexed', () => {
		dag.addFromDisk(PARSER_URI);
		let propNode = moduleMemberNode('x.parse;');
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'module', path: 'parser' });
		let type = inferNode(propNode, 'x.parse;', URI, scope, 0);
		assert.match('function', type.kind);
	});

	it('lazy-indexes the module from disk when not yet in the DAG', () => {
		// parser is NOT pre-indexed — the inferrer must call addFromDisk itself.
		dag.remove(PARSER_URI);
		let propNode = moduleMemberNode('x.parse;');
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'module', path: 'parser' });
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
		// x comes from spread, z from the pair
		assert.match(['x', 'z'], sort(map(t.fields, (f) => f.name)));
		assert.match(prim('int'), t.fields[0].type);
		assert.match({ kind: 'primitive', name: 'string', value: 'hello' }, t.fields[1].type);
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
		assert.match(union_(prim('int'), prim('string')), infer("let x = 1 || 'hello';"));
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
		// ucode's `delete` only accepts a property access (member/subscript).
		let t = infer("let x = delete obj.k;");
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
		assert.match([{ name: 'args', type: list_(unknown()) }], t.params);
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
		assert.match([{ name: 'a', type: unknown() }, { name: 'rest', type: list_(unknown()) }], t.params);
	});

	it('arrow function: rest param appears in inferred type params', () => {
		let t = infer("let f = (...args) => args;");
		assert.match('function', t.kind);
		assert.match([{ name: 'args', type: list_(unknown()) }], t.params);
	});

	it('rest param is in scope inside function body', () => {
		let text = "function f(...args) { return args; }";
		// position inside the body (after the '{')
		let bodyOffset = index(text, 'return');
		let scope = scopeFor(text, parse(text), bodyOffset);
		assert.match(list_(unknown()), scopeGet(scope, 'args'));
	});
});

describe('inferrer — object with string-literal keys', () => {
	it('"key": value is indexed as a record field', () => {
		let t = infer('let x = { "host": "localhost", "port": 8080 };');
		assert.match('record', t.kind);
		assert.match(['host', 'port'], sort(map(t.fields, (f) => f.name)));
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

describe('inferrer — builtins whose null depends on the arguments', () => {
	function typeAfter(text, name) {
		let tree = parse(text);
		return scopeGet(scopeFor(text, tree, length(text) - 1), name);
	}

	it('clock() is never null; clock(true) may be', () => {
		assert.match(list_(prim('int')), typeAfter("let t = clock();\nt;\n", 't'));
		assert.match({ kind: 'nullable', inner: list_(prim('int')) }, typeAfter("let t = clock(true);\nt;\n", 't'));
	});

	it('keys()/values() of a record are never null; of an unknown value may be', () => {
		assert.match(list_(prim('string')), typeAfter("let o = { a: 1 };\nlet k = keys(o);\nk;\n", 'k'));
		assert.match(list_({ kind: 'any' }), typeAfter("let o = { a: 1 };\nlet v = values(o);\nv;\n", 'v'));
		let text = "function f(x) {\n\tlet k = keys(x);\n\treturn k;\n}\n";
		assert.match({ kind: 'nullable', inner: list_(prim('string')) },
			scopeGet(scopeFor(text, parse(text), index(text, 'return k')), 'k'));
	});

	it('length() of a string, list or object is never null; of an unknown value may be', () => {
		for (let v in [ "'ab'", '[1, 2]', '{ a: 1 }', "(c ? 'ab' : [1])" ])
			assert.match(prim('int'), typeAfter(sprintf("let c = 1;\nlet n = length(%s);\nn;\n", v), 'n'), v);
		for (let v in [ '1', "(c ? 'ab' : null)" ])
			assert.match({ kind: 'nullable', inner: prim('int') },
				typeAfter(sprintf("let c = 1;\nlet n = length(%s);\nn;\n", v), 'n'), v);
		let text = "function f(x) {\n\tlet n = length(x);\n\treturn n;\n}\n";
		assert.match({ kind: 'nullable', inner: prim('int') },
			scopeGet(scopeFor(text, parse(text), index(text, 'return n')), 'n'));
	});

	it('a builtin whose null means a wrong argument type is not null for a right one', () => {
		let NI = { kind: 'nullable', inner: prim('int') };
		for (let c in [
			[ "index('ab', 'b')", prim('int') ], [ "rindex([1, 2], 2)", prim('int') ], [ "index(x, 1)", NI ],
			[ "join(',', [ 'a' ])", prim('string') ], [ "join(',', x)", { kind: 'nullable', inner: prim('string') } ],
			[ "b64enc('a')", prim('string') ],
		])
			assert.match(c[1], typeAfter(sprintf("function f(x) {\n\tlet n = %s;\n\treturn n;\n}\nlet n = %s;\nn;\n", c[0], c[0]), 'n'), c[0]);
		assert.match(list_(prim('int')), typeAfter("let n = uniq([1, 1]);\nn;\n", 'n'));
	});

	it('getenv(name) may be null; getenv() is the whole environment', () => {
		assert.match('nullable', typeAfter("let v = getenv('HOME');\nv;\n", 'v')?.kind);
		assert.match(true, typeAfter("let v = getenv();\nv;\n", 'v')?.kind !== 'nullable');
	});

	it('lc() and uc() are never null: they convert any value', () => {
		assert.match(prim('string'), typeAfter("let v = lc(null);\nv;\n", 'v'));
		assert.match(prim('string'), typeAfter("let v = uc(1);\nv;\n", 'v'));
	});

	it('proto(val, p) is val with p\'s fields; proto(val) may be null', () => {
		let o = typeAfter("let C = { m: function() {} };\nlet o = proto({ a: 1 }, C);\no;\n", 'o');
		assert.match(['a', 'm'], map(o?.fields ?? [], (f) => f.name));
		// An unknown prototype leaves the record open to more fields.
		assert.match({
			kind: 'record',
			fields: [{ name: 'a', type: { kind: 'primitive', name: 'int', value: 1 }, position: { line: 4, character: 16 } }],
			sourceUri: URI,
			open: true,
		}, typeAfter("function f(P) {\n\tlet o = proto({ a: 1 }, P);\n\treturn o;\n}\nlet q = proto({ a: 1 }, g());\nq;\n", 'q'));
		assert.match({ kind: 'nullable', inner: { kind: 'generic', base: 'dict', params: [unknown()] } },
			typeAfter("let o = proto({ a: 1 });\no;\n", 'o'));
	});

	it('a local named like a builtin is not refined', () => {
		let t = typeAfter("/** @returns {?int[]} */\nfunction clock() { return null; }\nlet t = clock();\nt;\n", 't');
		assert.match({ kind: 'nullable', inner: list_(prim('int')) }, t);
	});
});

