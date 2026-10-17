import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Open the marked text and hover at $0.
function hoverAt(marked) {
	let src = cursors(marked);
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
		textDocument: { uri: 'file:///t.uc' },
		position: src.at[0],
	}});
	return lsp.receive(proc);
}

// A hover result with these markdown lines.
function markdown(lines) {
	return { contents: { kind: 'markdown', value: join('\n', lines) } };
}

// The hover of a plain value: its name and type, nothing else.
function typed(text) {
	return markdown([ '```ucode', text, '```' ]);
}

const PARSE = markdown([
	'```ucode',
	'function parse(parser: object, source: string): object',
	'```',
	'',
	'Parse source text into a tree.',
	'',
	'**Parameters:**',
	'- `parser`: `object` — A parser from newParser().',
	'- `source`: `string` — The text to parse.',
	'',
]);

describe('textDocument/hover — feature coverage', () => {

	it('named import: shows inferred function signature with parameters', () => {
		let resp = hoverAt("import { parse } from 'parser';\n$0parse;\n");

		assert.match(1, resp.id);
		assert.match(PARSE, resp.result);
	});

	it('named import: prefers the re-export own JSDoc over the underlying definition', () => {
		// wrapper.uc does `export const thing = deep.thing` with its OWN JSDoc;
		// hover must show the wrapper's doc, not deep.uc's drilled-through doc.
		let resp = hoverAt("import { thing } from 'reexport.wrapper';\n$0thing;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function thing(): ?',
			'```',
			'',
			'Wrapper thing, documented on the re-export itself.',
			'',
		]), resp.result);
	});

	it('named import: shows JSDoc description from source module', () => {
		let resp = hoverAt("import { newParser } from 'parser';\n$0newParser;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function newParser(language: string): object',
			'```',
			'',
			'Create a parser for a language.',
			'',
			'**Parameters:**',
			'- `language`: `string` — The language name.',
			'',
		]), resp.result);
	});

	it('namespace import alias: shows module type with specifier', () => {
		let resp = hoverAt("import * as p from 'parser';\n$0p;\n");

		assert.match(1, resp.id);
		// parser.uc has no module doc: its first doc comment is newParser's.
		assert.match(markdown([
			'```ucode',
			"p: module 'parser'",
			'```',
			'',
			'**Members:**',
			'- `newParser`: `(language: string) => object`',
			'- `parse`: `(parser: object, source: string) => object`',
			'- `rootNode`: `(tree: ?) => ?`',
			'- `nodeType`: `(node: ?) => ?`',
			'- `text`: `(node: object, source: string) => string`',
			'- `parseString`: `(source: ?) => ?`',
			'',
		]), resp.result);
	});

	it('member expression property: shows type of accessed property with its parameters', () => {
		let resp = hoverAt("import * as p from 'parser';\np.$0parse;\n");

		assert.match(1, resp.id);
		assert.match(PARSE, resp.result);
	});

	it('stdlib builtin: shows function signature and description', () => {
		let resp = hoverAt("$0push;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function push(arr: list<T>, values: T): ?T',
			'```',
			'',
			'Pushes the given argument(s) to the given array.',
			'',
			'Returns the last pushed value.',
			'',
			'**Parameters:**',
			'- `arr`: `list<T>` — The array to push values to.',
			'- `values`: `T` — The values to push.',
			'',
			'**Example:**',
			'```ucode',
			'let x = [ 1, 2, 3 ];',
			'push(x, 4, 5, 6);    // 6',
			'print(x, "\\n");      // [ 1, 2, 3, 4, 5, 6 ]',
			'```',
			'',
		]), resp.result);
	});

	it('exported function with JSDoc: shows signature, description and Parameters section', () => {
		let resp = hoverAt("/**\n * Add two numbers.\n * @param {int} a\n * @param {int} b\n * @returns {int}\n */\nexport function add(a, b) { return a + b; };\n$0add;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function add(a: int, b: int): int',
			'```',
			'',
			'Add two numbers.',
			'',
			'**Parameters:**',
			'- `a`: `int`',
			'- `b`: `int`',
			'',
		]), resp.result);
	});

	it('optional-chain member obj?.prop: hover shows inner type, not nullable wrapper', () => {
		// Regression: inferMember wraps optional-chain results in {kind:'nullable'}.
		// hover must unwrap it before dispatch so the correct template is used.
		let resp = hoverAt("let obj = { x: 1 };\nobj?.$0x;\n");

		assert.match(1, resp.id);
		assert.match(typed('x: int'), resp.result);
	});

	it('record type object literal: shows field names in Members section', () => {
		let resp = hoverAt("let point = { x: 1, y: 2 };\n$0point;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'point: { x, y }',
			'```',
			'',
			'**Members:**',
			'- `x`: `int`',
			'- `y`: `int`',
			'',
		]), resp.result);
	});

	it('named import record: hover shows JSDoc description and member list', () => {
		// assert is a named import from utest bound to the utest.assert module.
		let resp = hoverAt("import { assert } from 'utest';\n$0assert;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			"assert: module 'utest.assert'",
			'```',
			'',
			'Assertion utilities for the utest framework.',
			'',
			'**Members:**',
			'- `fail`: `(msg: string) => ?`',
			'- `throws`: `(fn: () => ?, pattern: string | RegExp | Combinator<string>, msg: string) => ?`',
			'- `match`: `(expected: T | Combinator<T>, actual: T, msg: string) => ?`',
			'',
		]), resp.result);
	});

	it('consecutive hover requests on the same position return consistent results without a file change', () => {
		// Regression guard: scope-ID cache isolation must not break same-scope caching.
		// Two requests hitting the same node with the same scope should both return
		// the correct type (not UNKNOWN from a stale cache miss or a wrong hit).
		let src = cursors("let n = 42;\n$0n;\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: src.at[0],
		}});
		let resp1 = lsp.receive(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: src.at[0],
		}});
		let resp2 = lsp.receive(proc);

		assert.match(1, resp1.id);
		assert.match(2, resp2.id);
		assert.match(typed('n: int'), resp1.result);
		assert.match(typed('n: int'), resp2.result);
	});

	it('namespace import: hover shows module description from header comment', () => {
		// Fixtures with a plain /** description */ header expose the module doc
		// through the hover/module template. @description tags are not parsed.
		let resp = hoverAt("import * as hr from 'hover_record';\n$0hr;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			"hr: module 'hover_record'",
			'```',
			'',
			'Hover fixture: nested record and module doc.',
			'',
			'**Members:**',
			'- `utils`: `{ ops }`',
			'',
		]), resp.result);
	});

	it('nested record member: hover shows record type with inner fields', () => {
		// utils is an exported record; utils.ops is a nested object literal.
		// Hovering on 'ops' should show a record type listing its members.
		let resp = hoverAt("import { utils } from 'hover_record';\nutils.$0ops;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'ops: { upper }',
			'```',
			'',
			'**Members:**',
			'- `upper`: `(value: string) => string` — Converts the input to uppercase.',
			'',
		]), resp.result);
	});

	it('nested record member function: hover shows JSDoc description of inner method', () => {
		// utils.ops.upper is a function inside a nested object literal.
		// Hovering on 'upper' should show its JSDoc description.
		let resp = hoverAt("import { utils } from 'hover_record';\nutils.ops.$0upper;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function upper(value: string): string',
			'```',
			'',
			'Converts the input to uppercase.',
			'',
			'**Parameters:**',
			'- `value`: `string` — The value to convert.',
			'',
		]), resp.result);
	});

	it('named import record member: hover shows function JSDoc description', () => {
		// Cursor on 'match' in 'assert.match' — should show JSDoc for that specific method.
		let resp = hoverAt("import { assert } from 'utest';\nassert.$0match;\n");

		assert.match(1, resp.id);
		assert.match(markdown([
			'```ucode',
			'function match(expected: T | Combinator<T>, actual: T, msg: string): ?',
			'```',
			'',
			'Asserts that a value matches an expected value or combinator.',
			'',
			'**Parameters:**',
			'- `expected`: `T | Combinator<T>` — The expected value or combinator.',
			'- `actual`: `T` — The actual value to test.',
			'- `msg`: `string` — Custom failure message.',
			'',
			'**Example:**',
			'```ucode',
			'assert.match(2, 1 + 1);',
			'assert.match(contains("foo"), "foo bar");',
			'```',
			'',
		]), resp.result);
	});

	it('for-in loop variable at declaration site shows element type', () => {
		let resp = hoverAt("let xs = [1, 2, 3];\nfor (let $0item in xs) { item; }\n");
		assert.match(1, resp.id);
		assert.match(typed('item: int'), resp.result);
	});

	it('for-in over record: loop variable at declaration site shows string key type', () => {
		let resp = hoverAt("let obj = { a: 1, b: 2 };\nfor (let $0key in obj) { key; }\n");
		assert.match(1, resp.id);
		assert.match(typed('key: string'), resp.result);
	});

	it('for-in iterable (the collection) shows its own type, not empty', () => {
		let resp = hoverAt("let xs = [1, 2, 3];\nfor (let item in $0xs) { item; }\n");  // 'xs' (the iterable), not the loop var
		assert.match(1, resp.id);
		assert.match(typed('xs: list<int>'), resp.result);   // used to be null (routed to the loop-var path)
	});

	it('catch variable hover shows string type', () => {
		let resp = hoverAt("try { } catch(e) {\n    $0e;\n}\n");
		assert.match(1, resp.id);
		assert.match(typed('e: string'), resp.result);
	});

	it('type() narrowing: variable shows narrowed type inside if-branch', () => {
		// x is unknown initially; after type(x) === "string" check it should be string
		let resp = hoverAt("function f(x) {\n    if (type(x) === \"string\") {\n        $0x;\n    }\n}\n");
		assert.match(1, resp.id);
		assert.match(typed('x: string'), resp.result);
	});

	it('type() narrowing: variable shows narrowed type in else branch after !== check', () => {
		let resp = hoverAt("function f(x) {\n    if (type(x) !== \"string\") {\n    } else {\n        $0x;\n    }\n}\n");
		assert.match(1, resp.id);
		assert.match(typed('x: string'), resp.result);
	});
});
