import { describe, it, assert } from 'utest';
import * as lsp from 'client';

describe('initialize response', () => {
	it('returns capabilities and serverInfo', () => {
		let proc = lsp.connect();
		let resp = lsp.initialize(proc);
		let caps = resp.result.capabilities;

		assert.match(true, type(caps) === 'object');
		assert.match(1,    caps.textDocumentSync);
		assert.match(true, caps.hoverProvider);
		assert.match(true, caps.definitionProvider);
		assert.match(true, caps.referencesProvider);
		assert.match(true, caps.documentSymbolProvider);
		assert.match(true, caps.renameProvider);
		assert.match(true, type(caps.completionProvider)    === 'object');
		assert.match(true, type(caps.signatureHelpProvider) === 'object');
		assert.match('ucode-language-server', resp.result.serverInfo.name);

		let shutdownResp = lsp.shutdown(proc);
		assert.match(null, shutdownResp.result);
		assert.match(0, lsp.close(proc));
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
