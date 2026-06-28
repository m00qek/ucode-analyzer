import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/documentSymbol', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns symbols for all top-level declarations', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\nfunction greet() {}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);
		let names = sort(map(resp.result, (s) => s.name));

		assert.match(1, resp.id);
		assert.match(2, length(resp.result));
		assert.match('count', names[0]);
		assert.match('greet', names[1]);
	});

	it('returns empty list for a file with no declarations', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});

	it('finds nested function declarations inside a function body', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function outer() {\n  function inner() {}\n}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);
		let names = sort(map(resp.result, (s) => s.name));

		assert.match(2, length(resp.result));
		assert.match('inner', names[0]);
		assert.match('outer', names[1]);
	});

	it('finds function-valued object properties', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "const M = { handle: x => x, value: 1 };\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);
		let names = sort(map(resp.result, (s) => s.name));

		// M (CONSTANT) + handle (FUNCTION); value is plain, not emitted
		assert.match(2, length(resp.result));
		assert.match('M', names[0]);
		assert.match('handle', names[1]);
	});
});
