import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

const URI = 'file:///test.uc';

// The document most tests open, and the text didChange replaces it with.
const SRC = cursors('let $0x = 5;');
const CHANGED = cursors("let $0x = 'five';");

// The hover texts of the x of SRC and of CHANGED.
const INT = '```ucode\nx: int\n```';
const STRING = '```ucode\nx: string\n```';

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

// The hover text at position `at` (default: the `x` of SRC), or null.
function hoverAt(at, uri) {
	lsp.send(proc, { jsonrpc: '2.0', id: _id, method: 'textDocument/hover', params: {
		textDocument: { uri: uri ?? URI }, position: at ?? SRC.at[0],
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
		lsp.open(proc, URI, SRC.text);
		assert.match(INT, hoverAt());
	});

	it('hover is null for a document that was never opened', () => {
		assert.match(null, hoverAt(SRC.at[0], 'file:///not-open.uc'));
	});

	it('unknown request returns MethodNotFound', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32601, resp.error.code);
	});

	it('didChange replaces the text', () => {
		lsp.open(proc, URI, SRC.text);
		lsp.change(proc, URI, CHANGED.text, 2);
		assert.match(STRING, hoverAt(CHANGED.at[0]));
	});

	it('a pause in edits keeps the changed text, also when another document closes first', () => {
		const OTHER = 'file:///other.uc';
		lsp.open(proc, URI, SRC.text);
		lsp.open(proc, OTHER, SRC.text);
		lsp.change(proc, URI, CHANGED.text, 2);
		lsp.change(proc, OTHER, CHANGED.text, 2);
		assert.match(STRING, hoverAt(CHANGED.at[0]));
		close(OTHER);
		system('sleep 2');   // past the rebuild after a pause in edits (1 s)
		assert.match(STRING, hoverAt(CHANGED.at[0]));
		assert.match(null, hoverAt(CHANGED.at[0], OTHER));
	});

	it('didClose forgets the document', () => {
		lsp.open(proc, URI, SRC.text);
		close(URI);
		assert.match(null, hoverAt());
	});

	it('didChange before didOpen is ignored', () => {
		lsp.change(proc, 'file:///never-opened.uc', SRC.text, 2);
		assert.match(null, hoverAt(SRC.at[0], 'file:///never-opened.uc'));
	});

	it('didChange with empty contentChanges keeps the text', () => {
		lsp.open(proc, URI, SRC.text);
		lsp.send(proc, {
			jsonrpc: '2.0', method: 'textDocument/didChange',
			params: { textDocument: { uri: URI, version: 2 }, contentChanges: [] },
		});
		assert.match(INT, hoverAt());
	});

	it('textDocument/diagnostic reports on the open text', () => {
		lsp.open(proc, URI, 'let unused = 1;', 7);
		let report = lsp.documentDiagnostics(proc, URI);
		assert.match('full', report.kind);
		assert.match(['unused-var'], map(report.items, (d) => d.code));
	});
});
