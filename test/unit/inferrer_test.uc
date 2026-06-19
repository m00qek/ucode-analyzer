import { describe, it, assert, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag';
import { inferNode, buildScope } from 'ucode_language_server.inferrer';
import { makeScope, scopeSet } from 'ucode_language_server.scope';
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
});
