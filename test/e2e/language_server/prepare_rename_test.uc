import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/prepareRename', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns range and placeholder for a renameable identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\ncount;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareRename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match('count', resp.result.placeholder);
		assert.match(0, resp.result.range.start.line);
		assert.match(4, resp.result.range.start.character);
		assert.match(0, resp.result.range.end.line);
		assert.match(9, resp.result.range.end.character);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/prepareRename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(2, resp.id);
		assert.match(null, resp.result);
	});

	it('rename after prepareRename succeeds and uses placeholder text', () => {
		// Round-trip: prepareRename gives the token text, rename uses it.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nx;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 10, method: 'textDocument/prepareRename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
		}});
		let prep = lsp.receive(proc);
		assert.match('x', prep.result.placeholder);

		lsp.send(proc, { jsonrpc: '2.0', id: 11, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
			newName: 'y',
		}});
		let renamed = lsp.receive(proc);
		assert.match(2, length(renamed.result.changes['file:///t.uc']));
	});
});
