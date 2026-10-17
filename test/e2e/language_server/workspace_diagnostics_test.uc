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
		if (mine === null) die('no diagnostic entry for ws_a.uc');

		assert.match('full', mine.kind);
		assert.match(true, length(mine.items) >= 1);
	});

	it('reports the version of open documents, and null for the others', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///app/ws_v.uc', languageId: 'ucode', version: 7, text: 'let unused = 1;' },
		}});

		let report = lsp.workspaceDiagnostics(proc, []);
		assert.match(7, entryFor(report, 'file:///app/ws_v.uc')?.version);
		assert.match(null, entryFor(report, 'file:///app/test/fixtures/greet.uc')?.version);
		assert.match(true, entryFor(report, 'file:///app/test/fixtures/greet.uc') !== null);
	});

	it('returns unchanged on re-pull with a current resultId', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///app/ws_b.uc', languageId: 'ucode', version: 1, text: 'let unused = 1;' },
		}});

		let first = entryFor(lsp.workspaceDiagnostics(proc, []), 'file:///app/ws_b.uc');
		if (first === null) die('no diagnostic entry for ws_b.uc');
		assert.match('full', first.kind);

		// Re-pull carrying the previous resultId; nothing changed -> unchanged.
		let second = entryFor(
			lsp.workspaceDiagnostics(proc, [{ uri: 'file:///app/ws_b.uc', value: first.resultId }]),
			'file:///app/ws_b.uc');
		if (second === null) die('no re-pulled diagnostic entry for ws_b.uc');
		assert.match('unchanged', second.kind);
	});

	it('answers a superseded in-flight request instead of leaking it', () => {
		// Two workspace/diagnostic requests back-to-back: the second supersedes the
		// first's still-running background scan. The first id must still get a
		// response (ContentModified) — otherwise its client-side promise leaks.
		lsp.send(proc, { jsonrpc: '2.0', id: 7001, method: 'workspace/diagnostic', params: { previousResultIds: [] } });
		lsp.send(proc, { jsonrpc: '2.0', id: 7002, method: 'workspace/diagnostic', params: { previousResultIds: [] } });

		let byId = {};
		for (let i = 0; i < 2; i++) {
			let r = lsp.receive(proc);
			if (r === null) die('missing a workspace/diagnostic response (leaked request)');
			byId[sprintf('%d', r.id)] = r;
		}

		// Neither request is left unanswered — this is the regression the fix closes.
		assert.match(true, exists(byId, '7001') && exists(byId, '7002'));
		// When the first was still in flight (the usual case) it is aborted with
		// ContentModified (-32801); the later one carries the report.
		let first = byId['7001'];
		if (first.error !== null)
			assert.match(-32801, first.error.code);
	});

	it("reports the server's own sources when they are the workspace", () => {
		// /app is this checkout, so its sources are worked on, not a dependency.
		let report = lsp.workspaceDiagnostics(proc, []);
		let lsp_uc = filter(report.items, (item) => item.uri === 'file:///app/src/ucode_analyzer/language_server/lsp.uc');
		assert.match(1, length(lsp_uc));
	});
});
