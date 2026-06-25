import { describe, it, assert } from 'utest';
import { parseDoc, typeToString } from 'ucode_language_server.types.doc_parser';

// Helpers that build expected type objects.
function prim(name)          { return { kind: 'primitive', name }; }
function param(name)         { return { kind: 'param', name }; }
function ref(name, params)   { return { kind: 'ref', name, params: params ?? [] }; }
function list_(elem)         { return { kind: 'generic', base: 'list', params: [elem] }; }
function dict_(val)          { return { kind: 'generic', base: 'dict', params: [val] }; }
function nullable(inner)     { return { kind: 'nullable', inner }; }
function union_(...ms)       { return { kind: 'union', members: ms }; }
function fn_(params, ret)    { return { kind: 'function', params, return: ret }; }
function np(name, type)      { return { name, type }; }  // named function param
function ap(type)            { return { name: null, type }; }  // anon function param

describe('parseDoc — description and basic tags', () => {
	it('extracts description from multi-line comment', () => {
		let doc = parseDoc("/**\n * First line.\n * Second line.\n */");
		assert.match('First line.\nSecond line.', doc.description);
	});

	it('returns null description when none present', () => {
		let doc = parseDoc("/** @returns {string} */");
		assert.match(null, doc.description);
	});

	it('extracts @since and @deprecated', () => {
		let doc = parseDoc("/** @since 1.2 @deprecated use foo instead */");
		assert.match('1.2', doc.since);
		assert.match('use foo instead', doc.deprecated);
	});

	it('sets deprecated to true when no description given', () => {
		let doc = parseDoc("/** @deprecated */");
		assert.match(true, doc.deprecated);
	});
});

describe('parseDoc — @param', () => {
	it('extracts param name and type', () => {
		let doc = parseDoc("/** @param {string} name */");
		assert.match(1, length(doc.params));
		assert.match('name', doc.params[0].name);
		assert.match(prim('string'), doc.params[0].type);
		assert.match(false, doc.params[0].optional);
		assert.match(false, doc.params[0].rest);
	});

	it('extracts optional param', () => {
		let doc = parseDoc("/** @param {int} [count] */");
		assert.match('count', doc.params[0].name);
		assert.match(true, doc.params[0].optional);
	});

	it('extracts rest param', () => {
		let doc = parseDoc("/** @param {...string} args */");
		assert.match('args', doc.params[0].name);
		assert.match(true, doc.params[0].rest);
		assert.match(prim('string'), doc.params[0].type);
	});

	it('extracts param description', () => {
		let doc = parseDoc("/** @param {int} n The count */");
		assert.match('The count', doc.params[0].description);
	});

	it('extracts multiple params', () => {
		let doc = parseDoc("/** @param {string} a @param {int} b */");
		assert.match(2, length(doc.params));
		assert.match('a', doc.params[0].name);
		assert.match('b', doc.params[1].name);
	});
});

describe('parseDoc — @returns and @throws', () => {
	it('extracts returns type', () => {
		let doc = parseDoc("/** @returns {boolean} */");
		assert.match(prim('boolean'), doc.returns.type);
	});

	it('extracts throws type and description', () => {
		let doc = parseDoc("/** @throws {string} error message */");
		assert.match(prim('string'), doc.throws.type);
		assert.match('error message', doc.throws.description);
	});
});

describe('parseDoc — @template and type params', () => {
	it('collects template param names', () => {
		let doc = parseDoc("/** @template T */");
		assert.match(true, index(doc.template, 'T') >= 0);
	});

	it('parses template type as param kind', () => {
		let doc = parseDoc("/** @template T @param {T} item @returns {T} */");
		assert.match(param('T'), doc.params[0].type);
		assert.match(param('T'), doc.returns.type);
	});

	it('parses list<T> with template param', () => {
		let doc = parseDoc("/** @template T @returns {list<T>} */");
		assert.match(list_(param('T')), doc.returns.type);
	});

	it('does not treat PascalCase as param without @template', () => {
		let doc = parseDoc("/** @returns {MyType} */");
		assert.match(ref('MyType'), doc.returns.type);
	});
});

describe('parseDoc — @typedef', () => {
	it('extracts typedef name and type', () => {
		let doc = parseDoc("/** @typedef {string | int} Id */");
		assert.match('Id', doc.typedef.name);
		assert.match(union_(prim('string'), prim('int')), doc.typedef.type);
	});
});

describe('parseDoc — type forms', () => {
	it('parses primitive types', () => {
		for (let name in ['int', 'float', 'string', 'boolean', 'null', 'void']) {
			let doc = parseDoc(sprintf("/** @returns {%s} */", name));
			assert.match(prim(name), doc.returns.type);
		}
	});

	it('parses any type (* and any)', () => {
		let doc = parseDoc("/** @returns {*} */");
		assert.match({ kind: 'any' }, doc.returns.type);
	});

	it('parses list<T>', () => {
		let doc = parseDoc("/** @returns {list<string>} */");
		assert.match(list_(prim('string')), doc.returns.type);
	});

	it('parses T[] (array_type) as list<T>', () => {
		let doc = parseDoc("/** @returns {string[]} */");
		assert.match(list_(prim('string')), doc.returns.type);
	});

	it('parses nested T[][] as list<list<T>>', () => {
		let doc = parseDoc("/** @returns {int[][]} */");
		assert.match(list_(list_(prim('int'))), doc.returns.type);
	});

	it('parses parenthesized_type as the inner type', () => {
		let doc = parseDoc("/** @returns {(string|int)} */");
		assert.match(union_(prim('string'), prim('int')), doc.returns.type);
	});

	it('parses dict<V>', () => {
		let doc = parseDoc("/** @returns {dict<int>} */");
		assert.match(dict_(prim('int')), doc.returns.type);
	});

	it('parses record type', () => {
		let doc = parseDoc("/** @returns {{ name: string, count: int }} */");
		assert.match({ kind: 'record', fields: [
			{ name: 'name',  type: prim('string') },
			{ name: 'count', type: prim('int') },
		]}, doc.returns.type);
	});

	it('parses union type and flattens to list', () => {
		let doc = parseDoc("/** @returns {string | int | null} */");
		assert.match(union_(prim('string'), prim('int'), prim('null')), doc.returns.type);
	});

	it('parses nullable type', () => {
		let doc = parseDoc("/** @returns {?string} */");
		assert.match(nullable(prim('string')), doc.returns.type);
	});

	it('parses named generic type', () => {
		let doc = parseDoc("/** @typedef {Foo<string, int>} Bar */");
		assert.match(ref('Foo', [prim('string'), prim('int')]), doc.typedef.type);
	});

	it('parses function type with named params', () => {
		let doc = parseDoc("/** @param {(x: string, y: int) => boolean} fn */");
		assert.match(fn_([np('x', prim('string')), np('y', prim('int'))], prim('boolean')), doc.params[0].type);
	});

	it('parses anon function type with return', () => {
		let doc = parseDoc("/** @param {function(string, int): boolean} fn */");
		assert.match(fn_([ap(prim('string')), ap(prim('int'))], prim('boolean')), doc.params[0].type);
	});

	it('parses anon function type without return', () => {
		let doc = parseDoc("/** @param {function(string)} fn */");
		assert.match({ kind: 'function', params: [ap(prim('string'))], return: { kind: 'unknown' } }, doc.params[0].type);
	});
});

describe('parseDoc — @example', () => {
	it('captures a single @example block', () => {
		let doc = parseDoc("/**\n * @example\n * let x = foo(1, 2);\n */");
		assert.match(1, length(doc.examples));
		assert.match('let x = foo(1, 2);', doc.examples[0]);
	});

	it('captures multiple @example blocks independently', () => {
		let doc = parseDoc("/**\n * @example\n * foo(1);\n * @example\n * foo(2);\n */");
		assert.match(2, length(doc.examples));
		assert.match('foo(1);', doc.examples[0]);
		assert.match('foo(2);', doc.examples[1]);
	});

	it('returns empty examples array when no @example tags', () => {
		let doc = parseDoc("/** @param {string} x */");
		assert.match(0, length(doc.examples));
	});

	it('captures multi-line example body', () => {
		let doc = parseDoc("/**\n * @example\n * let a = 1;\n * let b = 2;\n */");
		assert.match(1, length(doc.examples));
		assert.match('let a = 1;\nlet b = 2;', doc.examples[0]);
	});
});

describe('typeToString', () => {
	it('primitive', () => { assert.match('string', typeToString(prim('string'))); });
	it('any',       () => { assert.match('*',      typeToString({ kind: 'any' })); });
	it('param',     () => { assert.match('T',      typeToString(param('T'))); });
	it('list',      () => { assert.match('list<int>',    typeToString(list_(prim('int')))); });
	it('dict',      () => { assert.match('dict<string>', typeToString(dict_(prim('string')))); });
	it('nullable',  () => { assert.match('?string', typeToString(nullable(prim('string')))); });
	it('union',     () => { assert.match('string | null', typeToString(union_(prim('string'), prim('null')))); });
	it('record',    () => { assert.match('{ a: int, b: string }', typeToString({ kind: 'record', fields: [{name:'a', type:prim('int')}, {name:'b', type:prim('string')}] })); });
	it('named generic', () => { assert.match('Foo<string, int>', typeToString(ref('Foo', [prim('string'), prim('int')]))); });
	it('function with named params', () => {
		assert.match('(x: string) => int', typeToString(fn_([np('x', prim('string'))], prim('int'))));
	});
	it('function with anon params', () => {
		assert.match('(string) => int', typeToString(fn_([ap(prim('string'))], prim('int'))));
	});
});
