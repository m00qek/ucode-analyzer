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

	it('finds nested function declarations inside a function body as children', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function outer() {\n  function inner() {}\n}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, length(resp.result));
		assert.match('outer', resp.result[0].name);
		assert.match(1, length(resp.result[0].children));
		assert.match('inner', resp.result[0].children[0].name);
	});

	it('finds function-valued object properties as children of the variable', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "const M = { handle: x => x, value: 1 };\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		// M (CONSTANT) at top level; handle (FUNCTION) as a child; value is plain, not emitted
		assert.match(1, length(resp.result));
		assert.match('M', resp.result[0].name);
		assert.match(1, length(resp.result[0].children));
		assert.match('handle', resp.result[0].children[0].name);
		assert.match(12, resp.result[0].children[0].kind);
	});
});
