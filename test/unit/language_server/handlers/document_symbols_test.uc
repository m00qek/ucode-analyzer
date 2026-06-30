import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { documentSymbols } from 'language_server.handlers.document_symbols';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('documentSymbols', () => {
	it('returns empty list for an empty file', () => {
		documents.open(URI, "", 1);
		assert.match(0, length(documentSymbols(documents.get(URI))));
	});

	it('includes a let variable with VARIABLE kind (13)', () => {
		let text = "let count = 0;\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('count', syms[0].name);
		assert.match(13, syms[0].kind);
	});

	it('includes a const with CONSTANT kind (14)', () => {
		let text = "const MAX = 100;\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('MAX', syms[0].name);
		assert.match(14, syms[0].kind);
	});

	it('includes an arrow function variable with FUNCTION kind (12)', () => {
		let text = "let fn = x => x;\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('fn', syms[0].name);
		assert.match(12, syms[0].kind);
	});

	it('includes a function declaration with FUNCTION kind (12)', () => {
		let text = "function greet() {}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('greet', syms[0].name);
		assert.match(12, syms[0].kind);
	});

	it('includes exported declarations', () => {
		let text = "export function hello() {}\nexport let x = 1;\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(2, length(syms));
		let names = sort(map(syms, (s) => s.name));
		assert.match('hello', names[0]);
		assert.match('x', names[1]);
	});

	it('selectionRange covers only the name, range covers the whole statement', () => {
		let text = "let value = 42;\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		// selectionRange is narrower (just 'value')
		assert.match(true, syms[0].selectionRange.start.character > syms[0].range.start.character
		                || syms[0].selectionRange.end.character < syms[0].range.end.character);
	});

	it('lists multiple declarations from a single file', () => {
		let text = "let a = 1;\nlet b = 2;\nfunction c() {}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(3, length(syms));
	});
});

describe('documentSymbols — nested declarations', () => {
	it('finds a function declaration nested inside another function as a child', () => {
		let text = "function outer() {\n  function inner() {}\n}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('outer', syms[0].name);
		assert.match(1, length(syms[0].children));
		assert.match('inner', syms[0].children[0].name);
		assert.match(12, syms[0].children[0].kind);
	});

	it('finds an arrow function nested inside a function body as a child', () => {
		let text = "function outer() {\n  let helper = x => x;\n}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('outer', syms[0].name);
		assert.match(1, length(syms[0].children));
		assert.match('helper', syms[0].children[0].name);
		assert.match(12, syms[0].children[0].kind);
	});

	it('finds a let variable inside a function body as a child', () => {
		let text = "function setup() {\n  let cfg = {};\n}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('setup', syms[0].name);
		assert.match(1, length(syms[0].children));
		assert.match('cfg', syms[0].children[0].name);
	});

	it('emits FUNCTION symbol for function-valued object property as a child of the variable', () => {
		let text = "const M = {\n  foo: x => x,\n  bar: 1,\n};\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('M', syms[0].name);
		assert.match(14, syms[0].kind);  // CONSTANT
		// foo (FUNCTION) is a child; bar is not a function so absent
		assert.match(1, length(syms[0].children));
		assert.match('foo', syms[0].children[0].name);
		assert.match(12, syms[0].children[0].kind);
	});

	it('does not emit symbols for non-function object properties', () => {
		let text = "const config = { host: 'localhost', port: 80 };\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		// Only config itself; host/port are plain values → no children
		assert.match(1, length(syms));
		assert.match('config', syms[0].name);
		assert.match(true, syms[0].children === null);
	});

	it('handles deep nesting: function inside function inside function', () => {
		let text = "function a() {\n  function b() {\n    function c() {}\n  }\n}\n";
		documents.open(URI, text, 1);

		let syms = documentSymbols(documents.get(URI));
		assert.match(1, length(syms));
		assert.match('a', syms[0].name);
		assert.match(12, syms[0].kind);
		assert.match(1, length(syms[0].children));
		assert.match('b', syms[0].children[0].name);
		assert.match(1, length(syms[0].children[0].children));
		assert.match('c', syms[0].children[0].children[0].name);
	});
});
