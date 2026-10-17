import { describe, it, assert, setup, teardown, any_order } from 'utest';
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

// The items with these labels, in the order given (one per label expected).
function withLabels(items, labels) {
	return map(labels, (l) => filter(items, (i) => i.label === l));
}

// The completions of the parser module's exports, in any order.
const PARSER_EXPORTS = any_order([
	{ label: 'newParser', kind: 3, detail: 'object', documentation: 'Create a parser for a language.',
		insertText: 'newParser(${1:language})', insertTextFormat: 2 },
	{ label: 'parse', kind: 3, detail: 'object', documentation: 'Parse source text into a tree.',
		insertText: 'parse(${1:parser}, ${2:source})', insertTextFormat: 2 },
	{ label: 'rootNode', kind: 6, detail: null, documentation: 'The root node of a tree.' },
	{ label: 'nodeType', kind: 6, detail: null, documentation: 'The type name of a node.' },
	{ label: 'text', kind: 3, detail: 'string', documentation: 'The source text a node spans.',
		insertText: 'text(${1:node}, ${2:source})', insertTextFormat: 2 },
	{ label: 'parseString', kind: 3, detail: null, documentation: null,
		insertText: 'parseString($1)', insertTextFormat: 2, tags: [ 1 ] },  // @deprecated
]);

describe('textDocument/completion', () => {

	it('includes declared local variable in results', () => {
		let resp = completeMarked("let answer = 42;\n$0");  // after the declaration

		assert.match(1, resp.id);
		assert.match([ [ { label: 'answer', kind: 6, detail: 'int' } ] ],
			withLabels(resp.result, [ 'answer' ]));
	});

	it('reflects new declaration added by didChange', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;\n");
		let src = cursors("let x = 1;\nlet y = 2;\n$0");  // after both declarations
		lsp.change(proc, 'file:///t.uc', src.text, 2);
		let resp = completeAt(src.at[0]);

		assert.match(1, resp.id);
		assert.match([
			[ { label: 'x', kind: 6, detail: 'int' } ],
			[ { label: 'y', kind: 6, detail: 'int' } ],
		], withLabels(resp.result, [ 'x', 'y' ]));
	});

	it('namespace import: p. offers only parser exports', () => {
		// Cursor right after the dot — trigger-character path.
		let resp = completeMarked("import * as p from 'parser';\nlet x = 5;\np.$0\n");

		assert.match(1, resp.id);
		assert.match(PARSER_EXPORTS, resp.result);   // and not the local x
	});

	it('namespace import: p.pa offers only parser exports', () => {
		// Cursor on a partially-typed property — member_expression primary path.
		let resp = completeMarked("import * as p from 'parser';\np.p$0a\n");

		// Every export: the client filters by the typed prefix.
		assert.match(PARSER_EXPORTS, resp.result);
	});

	it('named import record: assert. offers only assert members', () => {
		// assert is imported as a named import whose type is a record.
		let resp = completeMarked("import { assert } from 'utest';\nlet y = 1;\nassert.$0\n");

		assert.match(1, resp.id);
		// The members of utest.assert, and not the local y. (Their documentation
		// is utest's own, so it is left out.)
		assert.match(any_order([
			{ label: 'fail', kind: 3, insertText: 'fail(${1:msg})' },
			{ label: 'throws', kind: 3, insertText: 'throws(${1:fn}, ${2:pattern}, ${3:msg})' },
			{ label: 'match', kind: 3, insertText: 'match(${1:expected}, ${2:actual}, ${3:msg})' },
		]), map(resp.result, (i) => ({ label: i.label, kind: i.kind, insertText: i.insertText })));
	});

	it('general context includes language keywords with kind 14', () => {
		let resp = completeMarked("let x = 1;\n$0");
		let keywords = [ 'if', 'for', 'return', 'let', 'function' ];

		// Each keyword once, with kind 14 and nothing else.
		assert.match(map(keywords, (k) => [ { label: k, kind: 14 } ]),
			withLabels(resp.result, keywords));
	});

	it('union of records: member completion offers fields from all branches', () => {
		let resp = completeMarked("let x = true ? { alpha: 1 } : { beta: 2 };\nx.$0\n");

		assert.match(1, resp.id);
		assert.match(any_order([
			{ label: 'alpha', kind: 6, detail: 'int', documentation: null },
			{ label: 'beta', kind: 6, detail: 'int', documentation: null },
		]), resp.result);
	});
});
