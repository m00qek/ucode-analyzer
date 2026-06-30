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

describe('textDocument/selectionRange', () => {

	it('capability is advertised', () => {
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.selectionRangeProvider === true);
	});

	it('returns one SelectionRange per requested position', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nlet y = 2;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/selectionRange', params: {
			textDocument: { uri: 'file:///t.uc' },
			positions: [
				{ line: 0, character: 4 },
				{ line: 1, character: 4 },
			],
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(2, length(resp.result));
	});

	it('innermost range covers the identifier under the cursor', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let foo = 1;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/selectionRange', params: {
			textDocument: { uri: 'file:///t.uc' },
			positions: [{ line: 0, character: 4 }],
		}});
		let resp = lsp.receive(proc);
		let inner = resp.result[0].range;
		// 'foo' is at columns 4-6 on line 0
		assert.match(0, inner.start.line);
		assert.match(4, inner.start.character);
		assert.match(0, inner.end.line);
		assert.match(7, inner.end.character);
	});

	it('parent chain expands outward to the program', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function f() {\n  return 42;\n}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/selectionRange', params: {
			textDocument: { uri: 'file:///t.uc' },
			positions: [{ line: 1, character: 9 }],
		}});
		let resp = lsp.receive(proc);
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
