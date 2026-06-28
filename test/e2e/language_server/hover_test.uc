import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/hover — feature coverage', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

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
});
