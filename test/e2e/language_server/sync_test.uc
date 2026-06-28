import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

const DOC = {
	uri: 'file:///test.uc',
	languageId: 'ucode',
	version: 1,
	text: 'let x = 5;',
};

describe('LSP document sync', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('textDocument/hover returns inferred type for a variable', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0', id: 1,
			method: 'textDocument/hover',
			params: {
				textDocument: { uri: DOC.uri },
				position: { line: 0, character: 4 },  // cursor on 'x' in 'let x = 5;'
			},
		});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('markdown', resp.result.contents.kind);
		assert.match(true, index(resp.result.contents.value, 'int') >= 0);
	});

	it('textDocument/hover returns null for unopened document', () => {
		lsp.send(proc, {
			jsonrpc: '2.0', id: 1,
			method: 'textDocument/hover',
			params: {
				textDocument: { uri: 'file:///not-open.uc' },
				position: { line: 0, character: 0 },
			},
		});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('unknown request returns MethodNotFound', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32601, resp.error.code);
	});

	it('textDocument/didOpen is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});

	it('textDocument/didChange is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0',
			method: 'textDocument/didChange',
			params: {
				textDocument: { uri: DOC.uri, version: 2 },
				contentChanges: [{ text: 'let x = 99;' }],
			},
		});

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});

	it('textDocument/didClose is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0',
			method: 'textDocument/didClose',
			params: { textDocument: { uri: DOC.uri } },
		});

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});
});
