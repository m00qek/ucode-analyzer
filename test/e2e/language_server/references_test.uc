import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/references', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns all occurrences of an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let z = 0;\nz;\nz;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/references', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },  // on 'z' declaration
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(3, length(resp.result));  // declaration + 2 uses
		for (let loc in resp.result)
			assert.match('file:///t.uc', loc.uri);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/references', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },  // 'l' in 'let'
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('does not include same-named identifiers from a different scope', () => {
		// Each function has a parameter `x`; references on one must not include the other.
		let text = "function a(x) { return x; }\nfunction b(x) { return x; }\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/references', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 11 },  // `x` parameter in function a
		}});

		let resp = lsp.receive(proc);

		assert.match(2, resp.id);
		// Only 2 results: declaration + use inside a; function b's x is excluded.
		assert.match(2, length(resp.result));
		for (let loc in resp.result)
			assert.match(0, loc.range.start.line);
	});
});
