import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('textDocument/hover — feature coverage', () => {

	it('named import: shows inferred function signature with parameters', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { parse } from 'tree_sitter';\nparse;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'parse') >= 0);
		assert.match(true, index(val, 'string') >= 0);
		assert.match(true, index(val, 'Parameters') >= 0);
	});

	it('named import: shows JSDoc description from source module', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { ucode } from 'tree_sitter';\nucode;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'tree-sitter') >= 0);
	});

	it('namespace import alias: shows module type with specifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'tree_sitter') >= 0);
	});

	it('member expression property: shows type of accessed property with its parameters', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts.parse;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 3 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'parse') >= 0);
		assert.match(true, index(val, 'string') >= 0);
		assert.match(true, index(val, 'Parameters') >= 0);
	});

	it('stdlib builtin: shows function signature and description', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "push;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'push') >= 0);
		assert.match(true, index(val, 'Pushes') >= 0);
	});

	it('exported function with JSDoc: shows signature, description and Parameters section', () => {
		let text = "/**\n * Add two numbers.\n * @param {int} a\n * @param {int} b\n * @returns {int}\n */\nexport function add(a, b) { return a + b; };\nadd;\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 7, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'add') >= 0);
		assert.match(true, index(val, 'int') >= 0);
		assert.match(true, index(val, 'Add two numbers') >= 0);
		assert.match(true, index(val, 'Parameters') >= 0);
	});

	it('optional-chain member obj?.prop: hover shows inner type, not nullable wrapper', () => {
		// Regression: inferMember wraps optional-chain results in {kind:'nullable'}.
		// hover must unwrap it before dispatch so the correct template is used.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let obj = { x: 1 };\nobj?.x;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 5 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		// Should return a non-null hover result (inner type is int, not nullable).
		assert.match(true, resp.result !== null);
		assert.match(true, resp.result.contents.value !== '');
	});

	it('record type object literal: shows field names in Members section', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let point = { x: 1, y: 2 };\npoint;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, index(val, 'x') >= 0);
		assert.match(true, index(val, 'y') >= 0);
		assert.match(true, index(val, 'Members') >= 0);
	});

	it('named import record: hover shows JSDoc description and member list', () => {
		// assert is a named import from utest whose type is a record.
		// Its JSDoc says "Assertion utilities." and its members include match and throws.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { assert } from 'utest';\nassert;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(true, index(val, 'Assertion utilities') >= 0);
		assert.match(true, index(val, 'Members') >= 0);
		assert.match(true, index(val, 'match') >= 0);
	});

	it('consecutive hover requests on the same position return consistent results without a file change', () => {
		// Regression guard: scope-ID cache isolation must not break same-scope caching.
		// Two requests hitting the same node with the same scope should both return
		// the correct type (not UNKNOWN from a stale cache miss or a wrong hit).
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let n = 42;\nn;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});
		let resp1 = lsp.receive(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});
		let resp2 = lsp.receive(proc);

		assert.match(1, resp1.id);
		assert.match(2, resp2.id);
		assert.match(true, resp1.result !== null);
		assert.match(true, resp2.result !== null);
		assert.match(true, index(resp1.result.contents.value, 'int') >= 0);
		assert.match(true, index(resp2.result.contents.value, 'int') >= 0);
	});

	it('namespace import: hover shows module description from header comment', () => {
		// Fixtures with a plain /** description */ header expose the module doc
		// through the hover/module template. @description tags are not parsed.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as hr from 'fixtures.hover_record';\nhr;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(true, index(val, 'Hover fixture') >= 0);
	});

	it('nested record member: hover shows record type with inner fields', () => {
		// utils is an exported record; utils.ops is a nested object literal.
		// Hovering on 'ops' should show a record type listing its members.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { utils } from 'fixtures.hover_record';\nutils.ops;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 6 },  // 'o' of 'ops' in 'utils.ops'
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(true, index(val, 'Members') >= 0);
		assert.match(true, index(val, 'upper') >= 0);
	});

	it('nested record member function: hover shows JSDoc description of inner method', () => {
		// utils.ops.upper is a function inside a nested object literal.
		// Hovering on 'upper' should show its JSDoc description.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { utils } from 'fixtures.hover_record';\nutils.ops.upper;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 10 },  // 'u' of 'upper' in 'utils.ops.upper'
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(true, index(val, 'Converts the input') >= 0);
		assert.match(true, index(val, 'Parameters') >= 0);
	});

	it('named import record member: hover shows function JSDoc description', () => {
		// Cursor on 'match' in 'assert.match' — should show JSDoc for that specific method.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { assert } from 'utest';\nassert.match;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 7 },  // 'm' of 'match' in 'assert.match'
		}});

		let resp = lsp.receive(proc);
		let val = resp.result.contents.value;

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(true, index(val, 'Asserts that a value') >= 0);
		assert.match(true, index(val, 'Parameters') >= 0);
		assert.match(true, index(val, 'expected') >= 0);
	});
});
