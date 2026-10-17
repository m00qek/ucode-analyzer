import { describe, it, assert, setup, teardown, any_order } from 'utest';
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
		assert.match([ { position: src.at[0], label: ': string', kind: 1, paddingLeft: true } ],
			resp.result);
	});

	it('emits parameter name hints for a documented call', () => {
		let src = cursors("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\nadd($11, $22);\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		assert.match(any_order([
			{ position: src.at[1], label: 'x:', kind: 2, paddingRight: true },
			{ position: src.at[2], label: 'y:', kind: 2, paddingRight: true },
		]), resp.result);
	});

	it('skips param hint when arg identifier matches param name', () => {
		lsp.open(proc, 'file:///t.uc', "/**\n * @param {int} x\n */\nfunction f(x) { return x; }\nlet x = 1;\nf(x);\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		// Nor a type hint for the literal initializer of x.
		assert.match([], resp.result);
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
		assert.match([ { position: src.at[0], label: ': string', kind: 1, paddingLeft: true } ],
			resp.result);
	});
});
