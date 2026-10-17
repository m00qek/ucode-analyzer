import { describe, it, assert, setup, teardown, any_order } from 'utest';
import * as lsp from 'client';
import { cursors, locate } from 'cursor';
import * as fixture from 'fixture';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Open the cursors' text at uri and rename the symbol at $0 to newName.
function renameAt(id, uri, src, newName) {
	lsp.open(proc, uri, src.text);
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/rename', params: {
		textDocument: { uri }, position: src.at[0], newName,
	}});
	return lsp.receive(proc);
}

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

// The range of `name` at pos.
function rangeAt(pos, name) {
	return { start: pos, end: { line: pos.line, character: pos.character + length(name) } };
}

describe('textDocument/rename', () => {

	it('returns workspace edit replacing all occurrences', () => {
		let src = cursors("let $0$1count$2 = 0;\n$3count$4;\n");
		let resp = renameAt(1, 'file:///t.uc', src, 'total');
		let edits = resp.result.changes['file:///t.uc'];

		assert.match(1, resp.id);
		assert.match(any_order([
			{ range: span(src, 1, 2), newText: 'total' },
			{ range: span(src, 3, 4), newText: 'total' },
		]), edits);
	});

	it('returns null when cursor is not on an identifier', () => {
		let resp = renameAt(1, 'file:///t.uc', cursors("$0let x = 1;"), 'y');

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('cross-file: rename from importer propagates edits to declaring module', () => {
		let uri = 'file:///t_xrename.uc';
		let src = cursors("import { $1parse$2 } from 'parser';\n$0$3parse$4();\n");
		let resp = renameAt(10, uri, src, 'parseDoc');

		assert.match(10, resp.id);
		// Edits in the importer and the declaring module, nowhere else.
		let changes = resp.result.changes;
		assert.match(any_order([ uri, fixture.uri('parser.uc') ]), keys(changes));

		// Importing file must have edits (import specifier + call).
		assert.match(any_order([
			{ range: span(src, 1, 2), newText: 'parseDoc' },
			{ range: span(src, 3, 4), newText: 'parseDoc' },
		]), changes[uri]);

		// parser.uc must also have edits (the export declaration and the internal
		// call in parseString()).
		let parser = fixture.read('parser.uc');
		let decl = rangeAt(locate(parser, 'export function parse(', 0, length('export function ')), 'parse');
		let call = rangeAt(locate(parser, 'return parse(', 0, length('return ')), 'parse');
		assert.match(any_order([
			{ range: decl, newText: 'parseDoc' },
			{ range: call, newText: 'parseDoc' },
		]), changes[fixture.uri('parser.uc')]);
	});

	it('renames only the binding in scope, not same-named identifiers in other scopes', () => {
		// Two functions each declare a local `n`.  Renaming one must not affect the other.
		let src = cursors("function a($0$1n$2) { return $3n$4; }\nfunction b(n) { return n; }\n");
		let resp = renameAt(2, 'file:///t.uc', src, 'num');
		let edits = resp.result.changes['file:///t.uc'];

		// Only the parameter declaration + use inside a.  Function b unchanged.
		assert.match(any_order([
			{ range: span(src, 1, 2), newText: 'num' },
			{ range: span(src, 3, 4), newText: 'num' },
		]), edits);
	});
});
