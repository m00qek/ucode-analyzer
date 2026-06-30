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

describe('textDocument/codeAction', () => {

	it('returns a quickfix for == that replaces it with ===', () => {
		// Open a file with == so the server emits a hint diagnostic.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nlet y = x == 1;\ny;\n" },
		}});
		let notif = lsp.receiveNotification(proc);
		let hint = filter(notif.params.diagnostics, (d) => d.severity === 4)[0];
		assert.match(true, hint !== null);

		// Send the hint back as context for codeAction.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t.uc' },
			range: hint.range,
			context: { diagnostics: [hint] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));

		let action = resp.result[0];
		assert.match('quickfix', action.kind);
		assert.match(true, action.isPreferred);
		assert.match('===', action.edit.changes['file:///t.uc'][0].newText);
	});

	it('returns a quickfix for != that replaces it with !==', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t2.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nlet y = x != 1;\ny;\n" },
		}});
		let notif = lsp.receiveNotification(proc);
		let hint = filter(notif.params.diagnostics, (d) => d.severity === 4)[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t2.uc' },
			range: hint.range,
			context: { diagnostics: [hint] },
		}});

		let resp = lsp.receive(proc);
		assert.match('!==', resp.result[0].edit.changes['file:///t2.uc'][0].newText);
	});

	it('returns null when context diagnostics are empty', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t3.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nx;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t3.uc' },
			range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
			context: { diagnostics: [] },
		}});

		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});
});
