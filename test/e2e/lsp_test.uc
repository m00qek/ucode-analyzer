import { describe, it, assert } from 'utest';
import * as lsp from 'lsp_client';

describe('LSP lifecycle', () => {
	it('initialize returns capabilities and serverInfo', () => {
		let proc = lsp.connect();
		let resp = lsp.initialize(proc);

		assert.match(true, type(resp?.result?.capabilities) == 'object');
		assert.match('ucode-language-server', resp?.result?.serverInfo?.name);

		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('unknown request returns MethodNotFound', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);

		assert.match(1, resp?.id);
		assert.match(-32601, resp?.error?.code);

		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('textDocument/didOpen is accepted', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, {
			jsonrpc: '2.0',
			method: 'textDocument/didOpen',
			params: { textDocument: {
				uri: 'file:///test.uc', languageId: 'ucode', version: 1, text: 'let x = 5;'
			} }
		});

		// Notification has no response; server must still handle subsequent requests.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);
		assert.match(1, resp?.id);

		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('exit without shutdown returns non-zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(true, lsp.close(proc) != 0);
	});
});
