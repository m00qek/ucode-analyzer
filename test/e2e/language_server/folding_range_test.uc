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

describe('textDocument/foldingRange', () => {

	it('capability is advertised', () => {
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.foldingRangeProvider === true);
	});

	it('returns empty list for a file with no blocks', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});

	it('returns a range for a multi-line function body', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function foo() {\n  let x = 1;\n  return x;\n}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		assert.match(0, resp.result[0].startLine);
		assert.match(3, resp.result[0].endLine);
	});

	it('emits an imports range for multiple consecutive imports', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as a from 'utest';\nimport * as b from 'utest';\n\nlet x = 1;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		let imp = filter(resp.result, (r) => r.kind === 'imports')[0];
		assert.match(true, imp !== null);
		assert.match(0, imp.startLine);
		assert.match(1, imp.endLine);
	});
});
