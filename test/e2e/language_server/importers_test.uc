import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
import * as fs from 'fs';
import * as lsp from 'client';
import { cursors } from 'cursor';

// An open file sees the current exports of the files it imports, however they
// change: an edit in the editor or on disk.

// Module resolution checks the disk, so lib.uc lives in a scratch workspace.
let LIB_V1 = "/**\n * @returns {string}\n */\nexport function f() { return 'x'; };\n";
let LIB_V2 = "/**\n * @returns {function}\n */\nexport function f() { return () => 1; };\n";
let IMPORTER = cursors("import { f } from 'lib';\nlet $0s = f();\ns();\n");

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
	lsp.open(proc, uri, text);
}

function codes(report) {
	return map(report.items ?? [], (d) => d.code);
}

let _hoverId = 1;
function hoverS() {
	lsp.send(proc, { jsonrpc: '2.0', id: _hoverId++, method: 'textDocument/hover', params: {
		textDocument: { uri: B }, position: IMPORTER.at[0],
	}});
	return lsp.receive(proc).result?.contents?.value ?? '';
}

describe('importers of a changed file', () => {
	it('see an edit to the imported file in the editor', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER.text);
		let before = lsp.documentDiagnostics(proc, B);
		assert.match(['not-a-function'], codes(before));
		assert.match(contains('string'), hoverS());

		lsp.change(proc, LIB, LIB_V2, 2);

		let after = lsp.documentDiagnostics(proc, B, before.resultId);
		assert.match('full', after.kind);
		assert.match([], codes(after));
		assert.match(contains('function'), hoverS());
	});

	it('keep their diagnostics when only a function body changes', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER.text);
		let before = lsp.documentDiagnostics(proc, B);

		lsp.change(proc, LIB, replace(LIB_V1, "return 'x';", "let y = 'y'; return y;"), 2);

		assert.match('unchanged', lsp.documentDiagnostics(proc, B, before.resultId).kind);
	});

	it('see an edit to the imported file on disk', () => {
		open(B, IMPORTER.text);
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

	it('see a file they import appear on disk', () => {
		open(B, "import { g } from 'newlib';\ng();\n");
		let before = lsp.documentDiagnostics(proc, B);
		assert.match(contains(['unknown-import']), codes(before));

		fs.writefile(ws + '/src/newlib.uc', "export function g() {};\n");
		lsp.send(proc, { jsonrpc: '2.0', method: 'workspace/didChangeWatchedFiles', params: {
			changes: [{ uri: 'file://' + ws + '/src/newlib.uc', type: 1 }],
		}});

		let after = lsp.documentDiagnostics(proc, B, before.resultId);
		assert.match('full', after.kind);
		assert.match([], codes(after));
	});

	it('see a file they import deleted from disk', () => {
		open(B, IMPORTER.text);
		let before = lsp.documentDiagnostics(proc, B);
		assert.match(['not-a-function'], codes(before));

		fs.unlink(ws + '/src/lib.uc');
		lsp.send(proc, { jsonrpc: '2.0', method: 'workspace/didChangeWatchedFiles', params: {
			changes: [{ uri: LIB, type: 3 }],
		}});

		let after = lsp.documentDiagnostics(proc, B, before.resultId);
		assert.match('full', after.kind);
		assert.match(contains(['unknown-import']), codes(after));
	});
});

// The server asks the client to re-pull every diagnostic (a refresh) when a
// change may have altered other files' diagnostics, once per burst.
describe('diagnostic refreshes', () => {
	let REFRESH = ['workspace/diagnostic/refresh'];

	function watched(uri, type) {
		lsp.send(proc, { jsonrpc: '2.0', method: 'workspace/didChangeWatchedFiles', params: {
			changes: [{ uri, type }],
		}});
	}

	it('one for a burst of edits that change an imported interface', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER.text);
		lsp.settle(proc);
		for (let v = 2; v <= 6; v++)
			lsp.change(proc, LIB, (v % 2) ? LIB_V1 : LIB_V2, v);
		assert.match(REFRESH, lsp.settle(proc));
	});

	it('none when an edit leaves the exports as they were', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER.text);
		lsp.settle(proc);
		lsp.change(proc, LIB, replace(LIB_V1, "return 'x';", "let y = 'y'; return y;"), 2);
		assert.match([], lsp.settle(proc));
	});

	it('none for an edit to a file nothing imports', () => {
		open(B, IMPORTER.text);
		lsp.settle(proc);
		lsp.change(proc, B, IMPORTER.text + "let more = 1;\n", 2);
		assert.match([], lsp.settle(proc));
	});

	it('one when an imported file changes on disk', () => {
		open(B, IMPORTER.text);
		lsp.settle(proc);
		fs.writefile(ws + '/src/lib.uc', LIB_V2);
		watched(LIB, 2);
		assert.match(REFRESH, lsp.settle(proc));
	});

	it('one when a file appears that an import was waiting for', () => {
		open(B, "import { g } from 'newlib';\ng();\n");
		lsp.settle(proc);
		fs.writefile(ws + '/src/newlib.uc', "export function g() {};\n");
		watched('file://' + ws + '/src/newlib.uc', 1);
		assert.match(REFRESH, lsp.settle(proc));
	});

	it('none for a disk change to a file open in the editor', () => {
		open(LIB, LIB_V1);
		open(B, IMPORTER.text);
		lsp.settle(proc);
		fs.writefile(ws + '/src/lib.uc', LIB_V2);
		watched(LIB, 2);
		assert.match([], lsp.settle(proc));
	});
});
