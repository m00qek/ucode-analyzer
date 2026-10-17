import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import * as fs from 'fs';
import * as fixture from 'fixture';

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
		lsp.open(proc, fixture.uri('ws_a.uc'), 'let unused = 1;');

		let report = lsp.workspaceDiagnostics(proc, []);
		let mine = entryFor(report, fixture.uri('ws_a.uc'));
		if (mine === null) die('no diagnostic entry for ws_a.uc');

		assert.match('full', mine.kind);
		assert.match(true, length(mine.items) >= 1);
	});

	it('reports the version of open documents, and null for the others', () => {
		lsp.open(proc, fixture.uri('ws_v.uc'), 'let unused = 1;', 7);

		let report = lsp.workspaceDiagnostics(proc, []);
		assert.match(7, entryFor(report, fixture.uri('ws_v.uc'))?.version);
		assert.match(null, entryFor(report, fixture.uri('greet.uc'))?.version);
		assert.match(true, entryFor(report, fixture.uri('greet.uc')) !== null);
	});

	it('returns unchanged on re-pull with a current resultId', () => {
		lsp.open(proc, fixture.uri('ws_b.uc'), 'let unused = 1;');

		let first = entryFor(lsp.workspaceDiagnostics(proc, []), fixture.uri('ws_b.uc'));
		if (first === null) die('no diagnostic entry for ws_b.uc');
		assert.match('full', first.kind);

		// Re-pull carrying the previous resultId; nothing changed -> unchanged.
		let second = entryFor(
			lsp.workspaceDiagnostics(proc, [{ uri: fixture.uri('ws_b.uc'), value: first.resultId }]),
			fixture.uri('ws_b.uc'));
		if (second === null) die('no re-pulled diagnostic entry for ws_b.uc');
		assert.match('unchanged', second.kind);
	});

	it('answers a superseded in-flight request instead of leaking it', () => {
		// Two workspace/diagnostic requests in one batch: the second supersedes the
		// first's background scan, which the first has just started. The first id
		// must still get a response (ContentModified) — otherwise its client-side
		// promise leaks.
		lsp.sendAll(proc, [
			{ jsonrpc: '2.0', id: 7001, method: 'workspace/diagnostic', params: { previousResultIds: [] } },
			{ jsonrpc: '2.0', id: 7002, method: 'workspace/diagnostic', params: { previousResultIds: [] } },
		]);

		let byId = {};
		for (let i = 0; i < 2; i++) {
			let r = lsp.receive(proc);
			if (r === null) die(lsp.gone(proc, 'missing a workspace/diagnostic response'));
			byId[sprintf('%d', r.id)] = r;
		}

		// Neither request is left unanswered: the first, still scanning when the
		// second arrives, is aborted with ContentModified; the second carries the
		// report.
		assert.match(-32801, byId['7001']?.error?.code);
		assert.match(true, length(byId['7002']?.result?.items ?? []) > 0);
	});

	it("reports the server's own sources when they are the workspace", () => {
		// A checkout of the server: its package directory (selfSrcDir, beside the
		// script that starts it) is in the workspace, so its sources are worked
		// on, not a dependency. The bundled declarations come along for builtins.
		let ws = fs.mkdtemp('/tmp/self-src-XXXXXX');
		fs.mkdir(ws + '/src');
		fs.mkdir(ws + '/src/ucode_analyzer');
		system(['cp', '-R', '/app/src/ucode_analyzer/declarations', ws + '/src/ucode_analyzer/']);
		fs.writefile(ws + '/src/ucode_analyzer/own.uc', 'let unused = 1;\n');
		fs.writefile(ws + '/src/server.uc',
			"import { main } from 'ucode_analyzer.cli.server';\n" +
			"main(ARGV, sourcepath(0, true) + '/ucode_analyzer');\n");

		let self = lsp.spawn('ucode', [
			'-L', '/app/src', ws + '/src/server.uc', '--config', '/tmp', '--workspace', ws,
		]);
		lsp.initialize(self);
		let report = lsp.workspaceDiagnostics(self, []);
		lsp.shutdown(self);
		let status = lsp.close(self);
		system(['rm', '-rf', ws]);

		assert.match(0, status);
		let own = filter(report.items, (item) => item.uri === 'file://' + ws + '/src/ucode_analyzer/own.uc');
		assert.match(1, length(own));
	});
});
