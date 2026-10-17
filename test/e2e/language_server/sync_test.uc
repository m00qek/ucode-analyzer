import { describe, it, assert, setup, teardown, contains } from 'utest';
import * as lsp from 'client';

const DOC = {
	uri: 'file:///test.uc',
	languageId: 'ucode',
	version: 1,
	text: 'let x = 5;',
};

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('LSP document sync', () => {

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
		assert.match(contains('int'), resp.result.contents.value);
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

	it('didChange before didOpen does not crash the server', () => {
		lsp.send(proc, {
			jsonrpc: '2.0', method: 'textDocument/didChange',
			params: { textDocument: { uri: DOC.uri, version: 2 }, contentChanges: [{ text: 'let y = 1;' }] },
		});

		// Server must still respond to a subsequent request.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(-32601, lsp.receive(proc).error.code);
	});

	it('didChange with empty contentChanges does not crash the server', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });

		lsp.send(proc, {
			jsonrpc: '2.0', method: 'textDocument/didChange',
			params: { textDocument: { uri: DOC.uri, version: 2 }, contentChanges: [] },
		});

		// Server must still respond to a subsequent request.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(-32601, lsp.receive(proc).error.code);
	});

	it('textDocument/diagnostic returns a full report for an open document', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: DOC.uri, languageId: 'ucode', version: 7, text: DOC.text },
		}});

		let report = lsp.documentDiagnostics(proc, DOC.uri);
		assert.match('full', report.kind);
	});

	it('didClose is accepted and the server stays responsive (pull model)', () => {
		// Open a file that produces a diagnostic (unused variable) and pull it.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: DOC.uri, languageId: 'ucode', version: 1, text: 'let unused = 1;' },
		}});
		assert.match(true, length(lsp.documentDiagnostics(proc, DOC.uri).items) > 0);

		// Close the file — pull-model clients clear diagnostics themselves, so the
		// server sends nothing; it must simply remain responsive.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didClose',
			params: { textDocument: { uri: DOC.uri } },
		});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});
});
