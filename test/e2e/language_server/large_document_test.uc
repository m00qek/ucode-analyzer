import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';
import * as fixture from 'fixture';

let proc;
let URI = fixture.uri('large.uc');

beforeEach(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

afterEach(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// A document past the size diagnosed in a worker: `n` functions, the last
// reading an undefined `ghost`.
function large(n) {
	let text = '';
	for (let i = 0; i < n; i++)
		text += sprintf("export function f%d(a, b) {\n\tlet x = a + b;\n\tif (x > %d) return x;\n\treturn [a, b];\n};\n", i, i);
	return text + sprintf("f0(ghost, %d);\n", n);
}

function pull(id) {
	return { jsonrpc: '2.0', id, method: 'textDocument/diagnostic', params: { textDocument: { uri: URI } } };
}

function hover(id) {
	return { jsonrpc: '2.0', id, method: 'textDocument/hover',
		params: { textDocument: { uri: URI }, position: { line: 0, character: 16 } } };
}

describe('a large document', () => {
	it('is diagnosed while a hover is answered first', () => {
		let text = large(400);
		assert.match(true, length(text) > 16384);
		lsp.open(proc, URI, text);
		lsp.sendAll(proc, [ pull(1), hover(2) ]);
		assert.match(2, lsp.receive(proc).id);
		let r = lsp.receive(proc);
		assert.match(1, r.id);
		assert.match([ "'ghost' is not defined" ], map(r.result.items, (d) => d.message));
	});

	it('answers a pull its document changed under as ContentModified', () => {
		lsp.open(proc, URI, large(400));
		// Once the hover is answered, the pull before it is running.
		lsp.sendAll(proc, [ pull(3), hover(4) ]);
		assert.match(4, lsp.receive(proc).id);
		lsp.change(proc, URI, large(401), 2);
		let r = lsp.receive(proc);
		assert.match(3, r.id);
		assert.match(-32801, r.error?.code);

		lsp.send(proc, pull(5));
		let again = lsp.receive(proc);
		assert.match(5, again.id);
		assert.match([ "'ghost' is not defined" ], map(again.result.items, (d) => d.message));
	});
});
