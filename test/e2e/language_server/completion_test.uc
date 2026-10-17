import { describe, it, assert, setup, teardown, contains, not } from 'utest';
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

describe('textDocument/completion', () => {

	it('includes declared local variable in results', () => {
		lsp.open(proc, 'file:///t.uc', "let answer = 42;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // after the declaration
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['answer']), labels);
	});

	it('reflects new declaration added by didChange', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;\n");
		lsp.change(proc, 'file:///t.uc', "let x = 1;\nlet y = 2;\n", 2);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },  // after both declarations
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['x']), labels);
		assert.match(contains(['y']), labels);
	});

	it('namespace import: ts. offers only tree_sitter exports', () => {
		// Cursor right after the dot — trigger-character path.
		let text = "import * as ts from 'tree_sitter';\nlet x = 5;\nts.\n";
		lsp.open(proc, 'file:///t.uc', text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 3 },  // after 'ts.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['parse']), labels);     // ts export
		assert.match(not(contains(['x'])), labels);        // local — must NOT appear
	});

	it('namespace import: ts.pa offers only tree_sitter exports', () => {
		// Cursor on a partially-typed property — member_expression primary path.
		let text = "import * as ts from 'tree_sitter';\nts.pa\n";
		lsp.open(proc, 'file:///t.uc', text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 4 },  // on 'a' of 'ts.pa'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(contains(['parse']), labels);
	});

	it('named import record: assert. offers only assert members', () => {
		// assert is imported as a named import whose type is a record.
		let text = "import { assert } from 'utest';\nlet y = 1;\nassert.\n";
		lsp.open(proc, 'file:///t.uc', text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 7 },  // after 'assert.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['match']), labels);     // assert member
		assert.match(contains(['throws']), labels);    // assert member
		assert.match(not(contains('y')), labels);        // local — must NOT appear
	});

	it('general context includes language keywords with kind 14', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);
		let items = resp.result;
		let labels = map(items, (i) => i.label);

		// Keywords present
		assert.match(contains(['if']), labels);
		assert.match(contains(['for']), labels);
		assert.match(contains(['return']), labels);
		assert.match(contains(['let']), labels);
		assert.match(contains(['function']), labels);

		// Keywords have kind 14
		for (let item in items) {
			if (item.label === 'if')
				assert.match(14, item.kind);
		}
	});

	it('union of records: member completion offers fields from all branches', () => {
		let text = "let x = true ? { alpha: 1 } : { beta: 2 };\nx.\n";
		lsp.open(proc, 'file:///t.uc', text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 2 },
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['alpha']), labels);
		assert.match(contains(['beta']), labels);
	});
});
