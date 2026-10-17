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

// Open the cursors' text and ask for the selection ranges at positions.
function selectionRanges(src, positions) {
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/selectionRange', params: {
		textDocument: { uri: 'file:///t.uc' }, positions,
	}});
	return lsp.receive(proc);
}

describe('textDocument/selectionRange', () => {

	it('capability is advertised', () => {
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.selectionRangeProvider === true);
	});

	it('returns one SelectionRange per requested position', () => {
		let src = cursors("let $0x = 1;\nlet $1y = 2;\n");
		let resp = selectionRanges(src, [ src.at[0], src.at[1] ]);
		assert.match(1, resp.id);
		assert.match(2, length(resp.result));
	});

	it('innermost range covers the identifier under the cursor', () => {
		let src = cursors("let $0$1foo$2 = 1;\n");
		let resp = selectionRanges(src, [ src.at[0] ]);
		assert.match({ start: src.at[1], end: src.at[2] }, resp.result[0].range);
	});

	it('parent chain expands outward to the program', () => {
		let src = cursors("function f() {\n  return $042;\n}\n");
		let resp = selectionRanges(src, [ src.at[0] ]);
		// Walk the parent chain to check it grows monotonically.
		let cur = resp.result[0];
		let prev = null;
		while (cur) {
			if (prev) {
				assert.match(true,
					prev.range.start.line > cur.range.start.line ||
					(prev.range.start.line === cur.range.start.line &&
					 prev.range.start.character >= cur.range.start.character));
			}
			prev = cur;
			cur = cur.parent;
		}
	});
});
