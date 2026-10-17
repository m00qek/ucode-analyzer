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

// Send prepareRename at position.
function prepareRename(id, position) {
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/prepareRename', params: {
		textDocument: { uri: 'file:///t.uc' }, position,
	}});
	return lsp.receive(proc);
}

describe('textDocument/prepareRename', () => {

	it('returns range and placeholder for a renameable identifier', () => {
		let src = cursors("let $0$1count$2 = 0;\ncount;\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		let resp = prepareRename(1, src.at[0]);

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match('count', resp.result.placeholder);
		assert.match({ start: src.at[1], end: src.at[2] }, resp.result.range);
	});

	it('returns null when cursor is not on an identifier', () => {
		let src = cursors("$0let x = 1;");
		lsp.open(proc, 'file:///t.uc', src.text);

		let resp = prepareRename(2, src.at[0]);

		assert.match(2, resp.id);
		assert.match(null, resp.result);
	});

	it('rename after prepareRename succeeds and uses placeholder text', () => {
		// Round-trip: prepareRename gives the token text, rename uses it.
		let src = cursors("let $0x = 1;\nx;\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		let prep = prepareRename(10, src.at[0]);
		assert.match('x', prep.result.placeholder);

		lsp.send(proc, { jsonrpc: '2.0', id: 11, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: src.at[0],
			newName: 'y',
		}});
		let renamed = lsp.receive(proc);
		assert.match(2, length(renamed.result.changes['file:///t.uc']));
	});
});
