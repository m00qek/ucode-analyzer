import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/rename', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns workspace edit replacing all occurrences', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\ncount;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
			newName: 'total',
		}});

		let resp = lsp.receive(proc);
		let edits = resp.result.changes['file:///t.uc'];

		assert.match(1, resp.id);
		assert.match(2, length(edits));
		for (let e in edits)
			assert.match('total', e.newText);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
			newName: 'y',
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});
});
