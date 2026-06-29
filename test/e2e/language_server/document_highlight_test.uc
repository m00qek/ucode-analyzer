import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/documentHighlight', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns all occurrences of the identifier under cursor', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let z = 0;\nz;\nz;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentHighlight', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(3, length(resp.result));
		for (let h in resp.result)
			assert.match(1, h.kind);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/documentHighlight', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(2, resp.id);
		assert.match(null, resp.result);
	});

	it('is scope-aware: highlights only the binding in the correct scope', () => {
		let text = "function a(x) { return x; }\nfunction b(x) { return x; }\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/documentHighlight', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 11 },  // x in function a
		}});

		let resp = lsp.receive(proc);

		assert.match(3, resp.id);
		// Only 2 highlights: parameter + use inside a. Function b's x excluded.
		assert.match(2, length(resp.result));
		for (let h in resp.result)
			assert.match(0, h.range.start.line);
	});
});
