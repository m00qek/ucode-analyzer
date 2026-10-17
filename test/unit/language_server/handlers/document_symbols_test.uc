import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { documentSymbols } from 'ucode_analyzer.language_server.handlers.document_symbols';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

// The symbols of the text of `src` (from cursors()).
function symbolsOf(src) {
	documents.open(URI, src.text, 1);
	return documentSymbols(documents.get(URI));
}

// A DocumentSymbol whose range and selectionRange are marker pairs of `src`.
function sym(src, name, kind, r, sel, children) {
	let s = {
		name, kind,
		range: { start: src.at[r[0]], end: src.at[r[1]] },
		selectionRange: { start: src.at[sel[0]], end: src.at[sel[1]] },
	};
	if (children) s.children = children;
	return s;
}

// Names, kinds and nesting only.
function shape(syms) {
	return map(syms, (s) => s.children ? { name: s.name, kind: s.kind, children: shape(s.children) } : { name: s.name, kind: s.kind });
}

afterEach(() => documents.close(URI));

describe('documentSymbols', () => {
	it('returns empty list for an empty file', () => {
		documents.open(URI, "", 1);
		assert.match([], documentSymbols(documents.get(URI)));
	});

	it('includes a let variable with VARIABLE kind (13)', () => {
		let src = cursors("$0let $2count$3 = 0;$1\n");
		assert.match([ sym(src, 'count', 13, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('includes a const with CONSTANT kind (14)', () => {
		let src = cursors("$0const $2MAX$3 = 100;$1\n");
		assert.match([ sym(src, 'MAX', 14, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('includes an arrow function variable with FUNCTION kind (12)', () => {
		let src = cursors("$0let $2fn$3 = x => x;$1\n");
		assert.match([ sym(src, 'fn', 12, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('includes a function declaration with FUNCTION kind (12)', () => {
		let src = cursors("$0function $2greet$3() {}$1\n");
		assert.match([ sym(src, 'greet', 12, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('includes exported declarations', () => {
		// the range is the declaration, without `export` and the `;`
		let src = cursors("export $0function $2hello$3() {}$1;\nexport $4let $6x$7 = 1;$5\n");
		assert.match([
			sym(src, 'hello', 12, [ 0, 1 ], [ 2, 3 ]),
			sym(src, 'x', 13, [ 4, 5 ], [ 6, 7 ]),
		], symbolsOf(src));
	});

	it('selectionRange covers only the name, range covers the whole statement', () => {
		let src = cursors("$0let $2value$3 = 42;$1\n");
		assert.match([ sym(src, 'value', 13, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('lists multiple declarations from a single file', () => {
		let src = cursors("$0let $1a$2 = 1;$3\n$4let $5b$6 = 2;$7\n$8function c() {}$9\n");
		assert.match([
			sym(src, 'a', 13, [ 0, 3 ], [ 1, 2 ]),
			sym(src, 'b', 13, [ 4, 7 ], [ 5, 6 ]),
			{   // out of markers: `c` is columns 9–10 of line 2
				name: 'c', kind: 12, range: { start: src.at[8], end: src.at[9] },
				selectionRange: { start: { line: 2, character: 9 }, end: { line: 2, character: 10 } },
			},
		], symbolsOf(src));
	});
});

describe('documentSymbols — nested declarations', () => {
	it('finds a function declaration nested inside another function as a child', () => {
		let src = cursors("$0function $2outer$3() {\n  $4function $6inner$7() {}$5\n}$1\n");
		assert.match([
			sym(src, 'outer', 12, [ 0, 1 ], [ 2, 3 ], [ sym(src, 'inner', 12, [ 4, 5 ], [ 6, 7 ]) ]),
		], symbolsOf(src));
	});

	it('finds an arrow function nested inside a function body as a child', () => {
		let src = cursors("$0function $2outer$3() {\n  $4let $6helper$7 = x => x;$5\n}$1\n");
		assert.match([
			sym(src, 'outer', 12, [ 0, 1 ], [ 2, 3 ], [ sym(src, 'helper', 12, [ 4, 5 ], [ 6, 7 ]) ]),
		], symbolsOf(src));
	});

	it('finds a let variable inside a function body as a child', () => {
		let src = cursors("$0function $2setup$3() {\n  $4let $6cfg$7 = {};$5\n}$1\n");
		assert.match([
			sym(src, 'setup', 12, [ 0, 1 ], [ 2, 3 ], [ sym(src, 'cfg', 13, [ 4, 5 ], [ 6, 7 ]) ]),
		], symbolsOf(src));
	});

	it('emits FUNCTION symbol for function-valued object property as a child of the variable', () => {
		let src = cursors("$0const $2M$3 = {\n  $4$6foo$7: x => x$5,\n  bar: 1,\n};$1\n");
		// M is CONSTANT; foo (FUNCTION) is a child; bar is not a function so absent
		assert.match([
			sym(src, 'M', 14, [ 0, 1 ], [ 2, 3 ], [ sym(src, 'foo', 12, [ 4, 5 ], [ 6, 7 ]) ]),
		], symbolsOf(src));
	});

	it('does not emit symbols for non-function object properties', () => {
		let src = cursors("$0const $2config$3 = { host: 'localhost', port: 80 };$1\n");
		// Only config itself; host/port are plain values → no children
		assert.match([ sym(src, 'config', 14, [ 0, 1 ], [ 2, 3 ]) ], symbolsOf(src));
	});

	it('handles deep nesting: function inside function inside function', () => {
		let text = "function a() {\n  function b() {\n    function c() {}\n  }\n}\n";
		documents.open(URI, text, 1);

		assert.match([ { name: 'a', kind: 12, children: [
			{ name: 'b', kind: 12, children: [ { name: 'c', kind: 12 } ] },
		] } ], shape(documentSymbols(documents.get(URI))));
	});

	it('lists the symbols of a template', () => {
		let text = "{% let title = 'x'; %}\n<h1>{{ title }}</h1>\n{% function row(r) { %}<tr>{% let cls = r; %}</tr>{% } %}\n";
		documents.open(URI, text, 1);

		assert.match([
			{ name: 'title', kind: 13 },
			{ name: 'row', kind: 12, children: [ { name: 'cls', kind: 13 } ] },
		], shape(documentSymbols(documents.get(URI))));
	});

	it('lists an export that follows a comment', () => {
		documents.open(URI, "export /* c */ function f() {}\n", 1);
		assert.match(['f'], map(documentSymbols(documents.get(URI)), (s) => s.name));
	});
});
