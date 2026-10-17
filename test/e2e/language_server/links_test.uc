import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

function open(uri, text) {
	lsp.open(proc, uri, text);
}

describe('textDocument/linkedEditingRange and documentLink', () => {
	it('links the keywords of a colon-form block', () => {
		let src = cursors("$1for$2 (k in o):\n  y();\nend$3f$0or$4\n");
		open('file:///le.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/linkedEditingRange', params: {
			textDocument: { uri: 'file:///le.uc' }, position: src.at[0],
		}});
		let r = lsp.receive(proc).result;
		assert.match([
			{ start: src.at[1], end: src.at[2] },
			{ start: src.at[3], end: src.at[4] },
		], r?.ranges);
	});

	it('links an import to its module file', () => {
		let src = cursors("import * as fs from '$1fs$2';\n");
		open('file:///dl.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/documentLink', params: {
			textDocument: { uri: 'file:///dl.uc' },
		}});
		// fs is a builtin module: the link goes to its bundled declarations.
		let decl = '/app/src/ucode_analyzer/declarations/fs.d.uc';
		assert.match([
			{ range: { start: src.at[1], end: src.at[2] }, target: 'file://' + decl, tooltip: decl },
		], lsp.receive(proc).result);
	});
});
