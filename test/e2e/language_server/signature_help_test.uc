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

describe('textDocument/signatureHelp', () => {

	it('returns signature when cursor is inside a known function call', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 2 },  // inside f(...)
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(true, index(resp.result.signatures[0].label, 'f') >= 0);
	});

	it('returns null when cursor is not inside a call', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('returns null when cursor is before the opening paren', () => {
		// Cursor on the function name itself — not inside the arguments node.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // on 'f', before '('
		}});

		let resp = lsp.receive(proc);

		assert.match(null, resp.result);
	});

	it('returns signature for a namespace-import member call (ts.parse)', () => {
		// The callee is a member_expression — most common real-world pattern.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts.parse(p, s);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 9 },  // on 'p', first arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(true, index(resp.result.signatures[0].label, 'parse') >= 0);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a named import call (parse)', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { parse } from 'tree_sitter';\nparse(p, s);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 6 },  // on 'p', first arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'parse') >= 0);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a stdlib builtin call (push)', () => {
		// push(arr, values) — declared in stdlib.d.uc, always in scope.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "push([1], 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 10 },  // on '2', second arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'push') >= 0);
		assert.match(1, resp.result.activeParameter);
	});

	it('shows innermost call signature when calls are nested', () => {
		// f(g(1), 2) — cursor inside g() shows g's signature, not f's.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 4 },  // on '1' inside g(...)
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'g') >= 0);
		assert.match(false, index(resp.result.signatures[0].label, 'f(') >= 0);
	});

	it('shows outer call signature when cursor is on outer argument', () => {
		// f(g(1), 2) — cursor on '2' shows f's signature, not g's.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 8 },  // on '2', second arg of f
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'f') >= 0);
		assert.match(1, resp.result.activeParameter);
	});

	it('clamps activeParameter to last param when excess arguments are supplied', () => {
		// f has 2 params; calling with 3 args — activeParameter must not exceed 1.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2, 3);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 8 },  // on '3', third arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(1, resp.result.activeParameter);  // clamped from 2 to 1
	});
});
