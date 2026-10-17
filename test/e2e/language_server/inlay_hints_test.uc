import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let FULL_RANGE = { start: { line: 0, character: 0 }, end: { line: 9999, character: 0 } };
let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('textDocument/inlayHint', () => {

	it('capability is advertised in initialize response', () => {
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.inlayHintProvider === true);
	});

	it('returns empty list for a file with no hints', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 42;\nlet y = 'hello';\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});

	it('emits a type hint for a function-call initializer', () => {
		let src = cursors("function makeStr() { return 'hello'; }\nlet y$0 = makeStr();\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		let typeHints = filter(resp.result, (h) => h.kind === 1);
		assert.match(1, length(typeHints));
		assert.match(': string', typeHints[0].label);
		assert.match(src.at[0], typeHints[0].position);
	});

	it('emits parameter name hints for a documented call', () => {
		lsp.open(proc, 'file:///t.uc', "/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\nadd(1, 2);\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		let paramHints = filter(resp.result, (h) => h.kind === 2);
		assert.match(2, length(paramHints));
		let labels = sort(map(paramHints, (h) => h.label));
		assert.match('x:', labels[0]);
		assert.match('y:', labels[1]);
	});

	it('skips param hint when arg identifier matches param name', () => {
		lsp.open(proc, 'file:///t.uc', "/**\n * @param {int} x\n */\nfunction f(x) { return x; }\nlet x = 1;\nf(x);\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		let paramHints = filter(resp.result, (h) => h.kind === 2);
		assert.match(0, length(paramHints));
	});

	it('respects range: hints outside visible range are not returned', () => {
		// Only the `let a` line is in range.
		let src = cursors("function makeStr() { return 'x'; }\n$1let a$0 = makeStr();\n$2let b = makeStr();\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' },
			range: { start: src.at[1], end: src.at[2] },
		}});
		let resp = lsp.receive(proc);
		let typeHints = filter(resp.result, (h) => h.kind === 1);
		assert.match(1, length(typeHints));
		assert.match(src.at[0], typeHints[0].position);
	});
});
