import { describe, it, assert, setup, teardown, any_order } from 'utest';
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

// Open the cursors' text and ask for the highlights at $0.
function highlightAt(id, src) {
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/documentHighlight', params: {
		textDocument: { uri: 'file:///t.uc' },
		position: src.at[0],
	}});
	return lsp.receive(proc);
}

// A Text (kind 1) highlight from marker a to marker b.
function highlight(src, a, b) {
	return { range: { start: src.at[a], end: src.at[b] }, kind: 1 };
}

describe('textDocument/documentHighlight', () => {

	it('returns all occurrences of the identifier under cursor', () => {
		let src = cursors("let $0$1z$2 = 0;\n$3z$4;\n$5z$6;\n");
		let resp = highlightAt(1, src);

		assert.match(1, resp.id);
		assert.match(any_order([
			highlight(src, 1, 2), highlight(src, 3, 4), highlight(src, 5, 6),
		]), resp.result);
	});

	it('returns null when cursor is not on an identifier', () => {
		let resp = highlightAt(2, cursors("$0let x = 1;"));

		assert.match(2, resp.id);
		assert.match(null, resp.result);
	});

	it('is scope-aware: highlights only the binding in the correct scope', () => {
		let src = cursors("function a($0$1x$2) { return $3x$4; }\nfunction b(x) { return x; }\n");
		let resp = highlightAt(3, src);

		assert.match(3, resp.id);
		// Only the parameter + use inside a. Function b's x excluded.
		assert.match(any_order([ highlight(src, 1, 2), highlight(src, 3, 4) ]), resp.result);
	});
});
