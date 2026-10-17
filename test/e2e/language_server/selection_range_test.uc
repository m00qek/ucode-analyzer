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

// The SelectionRange whose ranges, innermost first, run between the pairs
// [a, b] of src's markers (or positions given as such).
function chain(src, pairs) {
	let at = (p) => (type(p) === 'int') ? src.at[p] : p;
	let sel = null;
	for (let i = length(pairs) - 1; i >= 0; i--)
		sel = { range: { start: at(pairs[i][0]), end: at(pairs[i][1]) }, parent: sel };
	return sel;
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
		// Each: identifier, declarator, declaration, program.
		let src = cursors("$2let $0x$3 = 1$4;$5\nlet $1y$6 = 2$7;$8\n$9");
		let line1 = { line: 1, character: 0 };
		let resp = selectionRanges(src, [ src.at[0], src.at[1] ]);
		assert.match(1, resp.id);
		assert.match([
			chain(src, [ [0, 3], [0, 4], [2, 5], [2, 9] ]),
			chain(src, [ [1, 6], [1, 7], [line1, 8], [2, 9] ]),
		], resp.result);
	});

	it('innermost range covers the identifier under the cursor', () => {
		let src = cursors("let $0$1foo$2 = 1;\n");
		let resp = selectionRanges(src, [ src.at[0] ]);
		assert.match({ start: src.at[1], end: src.at[2] }, resp.result[0].range);
	});

	it('parent chain expands outward to the program', () => {
		let src = cursors("$1function f() $2{\n  $3return $0$442$5;$6\n}$7\n$8");
		let resp = selectionRanges(src, [ src.at[0] ]);
		// The number, the return statement, the body, the function, the program.
		assert.match([ chain(src, [ [4, 5], [3, 6], [2, 7], [1, 7], [1, 8] ]) ], resp.result);
	});
});
