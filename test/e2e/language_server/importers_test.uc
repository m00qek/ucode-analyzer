import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
import * as fs from 'fs';
import * as lsp from 'client';

// An open file sees the current exports of the files it imports, however they
// change: an edit in the editor or on disk.

// Module resolution checks the disk, so lib.uc lives in a scratch workspace.
let LIB_V1 = "/**\n * @returns {string}\n */\nexport function f() { return 'x'; };\n";
let LIB_V2 = "/**\n * @returns {function}\n */\nexport function f() { return () => 1; };\n";
let IMPORTER = "import { f } from 'lib';\nlet s = f();\ns();\n";

let proc, ws, LIB, B;

beforeEach(() => {
	ws = fs.mkdtemp('/tmp/importers-XXXXXX');
	fs.mkdir(ws + '/src');
	fs.writefile(ws + '/src/lib.uc', LIB_V1);
	LIB = 'file://' + ws + '/src/lib.uc';
	B   = 'file://' + ws + '/src/b.uc';
	proc = lsp.connect(ws);
	lsp.initialize(proc);
});

afterEach(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
	system(['rm', '-rf', ws]);
});

function open(uri, text) {
	lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
		textDocument: { uri, languageId: 'ucode', version: 1, text },
	}});
}

function codes(report) {
	return map(report.items ?? [], (d) => d.code);
}

let _hoverId = 1;
function hoverS() {
	lsp.send(proc, { jsonrpc: '2.0', id: _hoverId++, method: 'textDocument/hover', params: {
		textDocument: { uri: B }, position: { line: 1, character: 4 },
	}});
	return lsp.receive(proc).result?.contents?.value ?? '';
}

describe('importers of a changed file', () => {
	it('see an edit to the imported file in the editor', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER);
		let before = lsp.documentDiagnostics(proc, B);
		assert.match(['not-a-function'], codes(before));
		assert.match(contains('string'), hoverS());

		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
			textDocument: { uri: LIB, version: 2 }, contentChanges: [{ text: LIB_V2 }],
		}});

		let after = lsp.documentDiagnostics(proc, B, before.resultId);
		assert.match('full', after.kind);
		assert.match([], codes(after));
		assert.match(contains('function'), hoverS());
	});

	it('keep their diagnostics when only a function body changes', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER);
		let before = lsp.documentDiagnostics(proc, B);

		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
			textDocument: { uri: LIB, version: 2 },
			contentChanges: [{ text: replace(LIB_V1, "return 'x';", "let y = 'y'; return y;") }],
		}});

		assert.match('unchanged', lsp.documentDiagnostics(proc, B, before.resultId).kind);
	});

	it('get one diagnostic refresh for a burst of edits', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER);
		for (let v = 2; v <= 6; v++)
			lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
				textDocument: { uri: LIB, version: v },
				contentChanges: [{ text: (v % 2) ? LIB_V1 : LIB_V2 }],
			}});
		system('sleep 1');  // past the refresh delay
		lsp.send(proc, { jsonrpc: '2.0', id: 77, method: 'workspace/symbol', params: { query: 'zzz' } });
		let r = lsp.receiveUntil(proc, 77);
		assert.match(['workspace/diagnostic/refresh'], r.requests);
	});

	it('see an edit to the imported file on disk', () => {
		open(B, IMPORTER);
		let before = lsp.documentDiagnostics(proc, B);
		assert.match(['not-a-function'], codes(before));

		fs.writefile(ws + '/src/lib.uc', LIB_V2);
		lsp.send(proc, { jsonrpc: '2.0', method: 'workspace/didChangeWatchedFiles', params: {
			changes: [{ uri: LIB, type: 2 }],
		}});

		let after = lsp.documentDiagnostics(proc, B, before.resultId);
		assert.match('full', after.kind);
		assert.match([], codes(after));
		assert.match(contains('function'), hoverS());
	});
});
