import { describe, it, assert, setup, teardown, contains, not } from 'utest';
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

describe('textDocument/hover — feature coverage', () => {

	it('named import: shows inferred function signature with parameters', () => {
		let resp = hoverAt("import { parse } from 'parser';\n$0parse;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('parse'), val);
		assert.match(contains('string'), val);
		assert.match(contains('Parameters'), val);
	});

	it('named import: prefers the re-export own JSDoc over the underlying definition', () => {
		// wrapper.uc does `export const thing = deep.thing` with its OWN JSDoc;
		// hover must show the wrapper's doc, not deep.uc's drilled-through doc.
		let resp = hoverAt("import { thing } from 'reexport.wrapper';\n$0thing;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('Wrapper thing'), val);   // re-export's own doc
		assert.match(not(contains('Deep thing')), val);       // not the drilled-through doc
	});

	it('named import: shows JSDoc description from source module', () => {
		let resp = hoverAt("import { newParser } from 'parser';\n$0newParser;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('Create a parser for a language'), val);
	});

	it('namespace import alias: shows module type with specifier', () => {
		let resp = hoverAt("import * as p from 'parser';\n$0p;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains("module 'parser'"), val);
	});

	it('member expression property: shows type of accessed property with its parameters', () => {
		let resp = hoverAt("import * as p from 'parser';\np.$0parse;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('parse'), val);
		assert.match(contains('string'), val);
		assert.match(contains('Parameters'), val);
	});

	it('stdlib builtin: shows function signature and description', () => {
		let resp = hoverAt("$0push;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('push'), val);
		assert.match(contains('Pushes'), val);
	});

	it('exported function with JSDoc: shows signature, description and Parameters section', () => {
		let resp = hoverAt("/**\n * Add two numbers.\n * @param {int} a\n * @param {int} b\n * @returns {int}\n */\nexport function add(a, b) { return a + b; };\n$0add;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('add'), val);
		assert.match(contains('int'), val);
		assert.match(contains('Add two numbers'), val);
		assert.match(contains('Parameters'), val);
	});

	it('optional-chain member obj?.prop: hover shows inner type, not nullable wrapper', () => {
		// Regression: inferMember wraps optional-chain results in {kind:'nullable'}.
		// hover must unwrap it before dispatch so the correct template is used.
		let resp = hoverAt("let obj = { x: 1 };\nobj?.$0x;\n");

		assert.match(1, resp.id);
		// Should return a non-null hover result (inner type is int, not nullable).
		assert.match(true, resp.result !== null);
		assert.match(true, resp.result.contents.value !== '');
	});

	it('record type object literal: shows field names in Members section', () => {
		let resp = hoverAt("let point = { x: 1, y: 2 };\n$0point;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(contains('x'), val);
		assert.match(contains('y'), val);
		assert.match(contains('Members'), val);
	});

	it('named import record: hover shows JSDoc description and member list', () => {
		// assert is a named import from utest whose type is a record.
		// Its JSDoc says "Assertion utilities." and its members include match and throws.
		let resp = hoverAt("import { assert } from 'utest';\n$0assert;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('Assertion utilities'), val);
		assert.match(contains('Members'), val);
		assert.match(contains('match'), val);
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
		assert.match(true, resp1.result !== null);
		assert.match(true, resp2.result !== null);
		assert.match(contains('int'), resp1.result.contents.value);
		assert.match(contains('int'), resp2.result.contents.value);
	});

	it('namespace import: hover shows module description from header comment', () => {
		// Fixtures with a plain /** description */ header expose the module doc
		// through the hover/module template. @description tags are not parsed.
		let resp = hoverAt("import * as hr from 'hover_record';\n$0hr;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('Hover fixture'), val);
	});

	it('nested record member: hover shows record type with inner fields', () => {
		// utils is an exported record; utils.ops is a nested object literal.
		// Hovering on 'ops' should show a record type listing its members.
		let resp = hoverAt("import { utils } from 'hover_record';\nutils.$0ops;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('Members'), val);
		assert.match(contains('upper'), val);
	});

	it('nested record member function: hover shows JSDoc description of inner method', () => {
		// utils.ops.upper is a function inside a nested object literal.
		// Hovering on 'upper' should show its JSDoc description.
		let resp = hoverAt("import { utils } from 'hover_record';\nutils.ops.$0upper;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('Converts the input'), val);
		assert.match(contains('Parameters'), val);
	});

	it('named import record member: hover shows function JSDoc description', () => {
		// Cursor on 'match' in 'assert.match' — should show JSDoc for that specific method.
		let resp = hoverAt("import { assert } from 'utest';\nassert.$0match;\n");
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('Asserts that a value'), val);
		assert.match(contains('Parameters'), val);
		assert.match(contains('expected'), val);
	});

	it('for-in loop variable at declaration site shows element type', () => {
		let resp = hoverAt("let xs = [1, 2, 3];\nfor (let $0item in xs) { item; }\n");
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('int'), resp.result.contents.value);
	});

	it('for-in over record: loop variable at declaration site shows string key type', () => {
		let resp = hoverAt("let obj = { a: 1, b: 2 };\nfor (let $0key in obj) { key; }\n");
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('string'), resp.result.contents.value);
	});

	it('for-in iterable (the collection) shows its own type, not empty', () => {
		let resp = hoverAt("let xs = [1, 2, 3];\nfor (let item in $0xs) { item; }\n");  // 'xs' (the iterable), not the loop var
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);   // used to be null (routed to the loop-var path)
		assert.match(contains('int'), resp.result.contents.value);
	});

	it('catch variable hover shows string type', () => {
		let resp = hoverAt("try { } catch(e) {\n    $0e;\n}\n");
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('string'), resp.result.contents.value);
	});

	it('type() narrowing: variable shows narrowed type inside if-branch', () => {
		// x is unknown initially; after type(x) === "string" check it should be string
		let resp = hoverAt("function f(x) {\n    if (type(x) === \"string\") {\n        $0x;\n    }\n}\n");
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('string'), resp.result.contents.value);
	});

	it('type() narrowing: variable shows narrowed type in else branch after !== check', () => {
		let resp = hoverAt("function f(x) {\n    if (type(x) !== \"string\") {\n    } else {\n        $0x;\n    }\n}\n");
		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(contains('string'), resp.result.contents.value);
	});
});
