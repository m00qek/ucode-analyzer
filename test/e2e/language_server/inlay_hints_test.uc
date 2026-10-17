import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';

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
		lsp.open(proc, 'file:///t.uc', "function makeStr() { return 'hello'; }\nlet y = makeStr();\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' }, range: FULL_RANGE,
		}});
		let resp = lsp.receive(proc);
		let typeHints = filter(resp.result, (h) => h.kind === 1);
		assert.match(1, length(typeHints));
		assert.match(': string', typeHints[0].label);
		assert.match(1, typeHints[0].position.line);
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
		lsp.open(proc, 'file:///t.uc', "function makeStr() { return 'x'; }\nlet a = makeStr();\nlet b = makeStr();\n");
		// Only line 1 is in range.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/inlayHint', params: {
			textDocument: { uri: 'file:///t.uc' },
			range: { start: { line: 1, character: 0 }, end: { line: 2, character: 0 } },
		}});
		let resp = lsp.receive(proc);
		let typeHints = filter(resp.result, (h) => h.kind === 1);
		assert.match(1, length(typeHints));
		assert.match(1, typeHints[0].position.line);
	});
});
