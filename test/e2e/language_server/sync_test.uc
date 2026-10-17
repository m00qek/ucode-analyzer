import { describe, it, assert, setup, teardown, contains } from 'utest';
import * as lsp from 'client';

const URI = 'file:///test.uc';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

let _id = 1;

// The hover text at the `x` of `let x = …` on the first line, or null.
function hoverX(uri) {
	lsp.send(proc, { jsonrpc: '2.0', id: _id, method: 'textDocument/hover', params: {
		textDocument: { uri: uri ?? URI }, position: { line: 0, character: 4 },
	}});
	let resp = lsp.receive(proc);
	assert.match(_id++, resp.id);
	return resp.result?.contents?.value ?? null;
}

function close(uri) {
	lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didClose',
		params: { textDocument: { uri } } });
}

describe('LSP document sync', () => {
	it('didOpen makes the text available', () => {
		lsp.open(proc, URI, 'let x = 5;');
		assert.match(contains('int'), hoverX());
	});

	it('hover is null for a document that was never opened', () => {
		assert.match(null, hoverX('file:///not-open.uc'));
	});

	it('unknown request returns MethodNotFound', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32601, resp.error.code);
	});

	it('didChange replaces the text', () => {
		lsp.open(proc, URI, 'let x = 5;');
		lsp.change(proc, URI, "let x = 'five';", 2);
		assert.match(contains('string'), hoverX());
	});

	it('didClose forgets the document', () => {
		lsp.open(proc, URI, 'let x = 5;');
		close(URI);
		assert.match(null, hoverX());
	});

	it('didChange before didOpen is ignored', () => {
		lsp.change(proc, 'file:///never-opened.uc', 'let x = 1;', 2);
		assert.match(null, hoverX('file:///never-opened.uc'));
	});

	it('didChange with empty contentChanges keeps the text', () => {
		lsp.open(proc, URI, 'let x = 5;');
		lsp.send(proc, {
			jsonrpc: '2.0', method: 'textDocument/didChange',
			params: { textDocument: { uri: URI, version: 2 }, contentChanges: [] },
		});
		assert.match(contains('int'), hoverX());
	});

	it('textDocument/diagnostic reports on the open text', () => {
		lsp.open(proc, URI, 'let unused = 1;', 7);
		let report = lsp.documentDiagnostics(proc, URI);
		assert.match('full', report.kind);
		assert.match(['unused-var'], map(report.items, (d) => d.code));
	});
});
