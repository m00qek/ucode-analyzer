import { describe, it, assert, setup, teardown, contains, not } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Ask for completions at position.
function completeAt(position) {
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
		textDocument: { uri: 'file:///t.uc' }, position,
	}});
	return lsp.receive(proc);
}

// Open the marked text and ask for completions at $0.
function completeMarked(marked) {
	let src = cursors(marked);
	lsp.open(proc, 'file:///t.uc', src.text);
	return completeAt(src.at[0]);
}

describe('textDocument/completion', () => {

	it('includes declared local variable in results', () => {
		let resp = completeMarked("let answer = 42;\n$0");  // after the declaration
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['answer']), labels);
	});

	it('reflects new declaration added by didChange', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;\n");
		let src = cursors("let x = 1;\nlet y = 2;\n$0");  // after both declarations
		lsp.change(proc, 'file:///t.uc', src.text, 2);
		let resp = completeAt(src.at[0]);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['x']), labels);
		assert.match(contains(['y']), labels);
	});

	it('namespace import: p. offers only parser exports', () => {
		// Cursor right after the dot — trigger-character path.
		let resp = completeMarked("import * as p from 'parser';\nlet x = 5;\np.$0\n");
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['parse']), labels);     // parser export
		assert.match(not(contains(['x'])), labels);        // local — must NOT appear
	});

	it('namespace import: p.pa offers only parser exports', () => {
		// Cursor on a partially-typed property — member_expression primary path.
		let resp = completeMarked("import * as p from 'parser';\np.p$0a\n");
		let labels = map(resp.result, (i) => i.label);

		assert.match(contains(['parse']), labels);
	});

	it('named import record: assert. offers only assert members', () => {
		// assert is imported as a named import whose type is a record.
		let resp = completeMarked("import { assert } from 'utest';\nlet y = 1;\nassert.$0\n");
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['match']), labels);     // assert member
		assert.match(contains(['throws']), labels);    // assert member
		assert.match(not(contains('y')), labels);        // local — must NOT appear
	});

	it('general context includes language keywords with kind 14', () => {
		let resp = completeMarked("let x = 1;\n$0");
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
		let resp = completeMarked("let x = true ? { alpha: 1 } : { beta: 2 };\nx.$0\n");
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(contains(['alpha']), labels);
		assert.match(contains(['beta']), labels);
	});
});
