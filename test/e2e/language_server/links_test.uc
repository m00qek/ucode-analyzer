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

function open(uri, text) {
	lsp.open(proc, uri, text);
}

describe('textDocument/linkedEditingRange and documentLink', () => {
	it('links the keywords of a colon-form block', () => {
		open('file:///le.uc', "for (k in o):\n  y();\nendfor\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/linkedEditingRange', params: {
			textDocument: { uri: 'file:///le.uc' }, position: { line: 2, character: 4 },
		}});
		let r = lsp.receive(proc).result;
		assert.match(2, length(r?.ranges ?? []));
		assert.match({ line: 2, character: 3 }, r.ranges[1].start);
	});

	it('links an import to its module file', () => {
		open('file:///dl.uc', "import * as fs from 'fs';\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/documentLink', params: {
			textDocument: { uri: 'file:///dl.uc' },
		}});
		let links = lsp.receive(proc).result;
		assert.match(1, length(links ?? []));
		assert.match(true, substr(links[0].target, -8) === '/fs.d.uc');
	});
});
