import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/completion', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('includes declared local variable in results', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let answer = 42;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // after the declaration
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'answer') >= 0);
	});

	it('reflects new declaration added by didChange', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
			textDocument: { uri: 'file:///t.uc', version: 2 },
			contentChanges: [{ text: "let x = 1;\nlet y = 2;\n" }],
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },  // after both declarations
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'x') >= 0);
		assert.match(true, index(labels, 'y') >= 0);
	});

	it('namespace import: ts. offers only tree_sitter exports', () => {
		// Cursor right after the dot — trigger-character path.
		let text = "import * as ts from 'tree_sitter';\nlet x = 5;\nts.\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 3 },  // after 'ts.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'parse') >= 0);     // ts export
		assert.match(false, index(labels, 'x') >= 0);        // local — must NOT appear
	});

	it('namespace import: ts.pa offers only tree_sitter exports', () => {
		// Cursor on a partially-typed property — member_expression primary path.
		let text = "import * as ts from 'tree_sitter';\nts.pa\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 4 },  // on 'a' of 'ts.pa'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(true, index(labels, 'parse') >= 0);
	});

	it('named import record: assert. offers only assert members', () => {
		// assert is imported as a named import whose type is a record.
		let text = "import { assert } from 'utest';\nlet y = 1;\nassert.\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 7 },  // after 'assert.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'match') >= 0);     // assert member
		assert.match(true, index(labels, 'throws') >= 0);    // assert member
		assert.match(false, index(labels, 'y') >= 0);        // local — must NOT appear
	});
});
