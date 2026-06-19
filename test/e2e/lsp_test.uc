import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'lsp_client';

const DOC = {
	uri: 'file:///test.uc',
	languageId: 'ucode',
	version: 1,
	text: 'let x = 5;',
};

// Standalone: needs to inspect the initialize response itself.
describe('initialize response', () => {
	it('returns capabilities and serverInfo', () => {
		let proc = lsp.connect();
		let resp = lsp.initialize(proc);

		assert.match(true, type(resp.result.capabilities) === 'object');
		assert.match(1, resp.result.capabilities.textDocumentSync);
		assert.match('ucode-language-server', resp.result.serverInfo.name);

		let shutdownResp = lsp.shutdown(proc);
		assert.match(null, shutdownResp.result);
		assert.match(0, lsp.close(proc));
	});
});

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

// Standalone: afterEach shutdown would conflict with the server already having exited.
describe('exit behavior', () => {
	it('exit without shutdown returns non-zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(true, lsp.close(proc) !== 0);
	});
});
