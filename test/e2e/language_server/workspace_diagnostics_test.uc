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

let entryFor = function(report, uri) {
	for (let item in report.items)
		if (item.uri === uri) return item;
	return null;
};

describe('workspace/diagnostic', () => {

	it('reports diagnostics for an open workspace file', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///app/ws_a.uc', languageId: 'ucode', version: 1, text: 'let unused = 1;' },
		}});

		let report = lsp.workspaceDiagnostics(proc, []);
		let mine = entryFor(report, 'file:///app/ws_a.uc');

		assert.match(true, mine !== null);
		assert.match('full', mine.kind);
		assert.match(true, length(mine.items) >= 1);
	});

	it('returns unchanged on re-pull with a current resultId', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///app/ws_b.uc', languageId: 'ucode', version: 1, text: 'let unused = 1;' },
		}});

		let first = entryFor(lsp.workspaceDiagnostics(proc, []), 'file:///app/ws_b.uc');
		assert.match('full', first.kind);

		// Re-pull carrying the previous resultId; nothing changed -> unchanged.
		let second = entryFor(
			lsp.workspaceDiagnostics(proc, [{ uri: 'file:///app/ws_b.uc', value: first.resultId }]),
			'file:///app/ws_b.uc');
		assert.match('unchanged', second.kind);
	});

	it("excludes the server's own bundled sources (selfSrcDir) from the report", () => {
		// Nothing user-facing is open; /app/src is selfSrcDir and must be excluded.
		let report = lsp.workspaceDiagnostics(proc, []);
		let fromSrc = filter(report.items, (item) => index(item.uri, 'file:///app/src/') === 0);
		assert.match(0, length(fromSrc));
	});
});
