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

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

// The DocumentSymbol `name` of this SymbolKind: its declaration from marker a
// to b of src, its name from c to d.
function symbol(src, name, kind, a, b, c, d) {
	return { name, kind, range: span(src, a, b), selectionRange: span(src, c, d) };
}

describe('textDocument/documentSymbol', () => {

	it('returns symbols for all top-level declarations', () => {
		let src = cursors("$1let $3count$4 = 0;$2\n$5function $7greet$8() {}$6\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(any_order([
			symbol(src, 'count', 13, 1, 2, 3, 4),   // Variable
			symbol(src, 'greet', 12, 5, 6, 7, 8),   // Function
		]), resp.result);
	});

	it('returns empty list for a file with no declarations', () => {
		lsp.open(proc, 'file:///t.uc', "");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});

	it('finds nested function declarations inside a function body as children', () => {
		let src = cursors("$1function $3outer$4() {\n  $5function $7inner$8() {}$6\n}$2\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match([ {
			...symbol(src, 'outer', 12, 1, 2, 3, 4),
			children: [ symbol(src, 'inner', 12, 5, 6, 7, 8) ],
		} ], resp.result);
	});

	it('finds function-valued object properties as children of the variable', () => {
		let src = cursors("$1const $3M$4 = { $5$7handle$8: x => x$6, value: 1 };$2\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		// M (CONSTANT) at top level; handle (FUNCTION) as a child; value is plain, not emitted
		assert.match([ {
			...symbol(src, 'M', 14, 1, 2, 3, 4),
			children: [ symbol(src, 'handle', 12, 5, 6, 7, 8) ],
		} ], resp.result);
	});
});
