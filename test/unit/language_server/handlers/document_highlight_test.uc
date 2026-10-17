import { describe, it, assert, afterEach, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { documentHighlight } from 'ucode_analyzer.language_server.handlers.document_highlight';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

// Open the text of `src` (from cursors()) and highlight the name at $0.
function highlightAt(src) {
	documents.open(URI, src.text, 1);
	return documentHighlight(URI, documents.get(URI), src.at[0]);
}

afterEach(() => documents.close(URI));

describe('documentHighlight', () => {
	it('returns null when cursor is not on an identifier', () => {
		// 'let' is an anonymous token
		assert.match(null, highlightAt(cursors("$0let x = 1;\n")));
	});

	it('returns null for position beyond end of file', () => {
		documents.open(URI, "let x = 1;\n", 1);
		assert.match(null, documentHighlight(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('returns all occurrences as highlights', () => {
		let src = cursors("let $0$1z$2 = 0;\n$3z$4;\n$5z$6;\n");
		assert.match(any_order([
			{ start: src.at[1], end: src.at[2] },
			{ start: src.at[3], end: src.at[4] },
			{ start: src.at[5], end: src.at[6] },
		]), map(highlightAt(src), (h) => h.range));
	});

	it('each highlight has kind 1 (Text)', () => {
		let src = cursors("let $0$1x$2 = 1;\n$3x$4;\n");
		assert.match(any_order([
			{ range: { start: src.at[1], end: src.at[2] }, kind: 1 },
			{ range: { start: src.at[3], end: src.at[4] }, kind: 1 },
		]), highlightAt(src));
	});

	it('highlight ranges span the exact identifier token', () => {
		let src = cursors("let $0$1count$2 = 0;\n");
		assert.match([ { range: { start: src.at[1], end: src.at[2] }, kind: 1 } ], highlightAt(src));
	});

	it('is scope-aware: does not cross function boundaries', () => {
		// on the 'x' parameter in function a
		let src = cursors("function a($0$1x$2) { return $3x$4; }\nfunction b(x) { return x; }\n");
		let highlights = highlightAt(src);
		// Only 2: parameter declaration + use inside a
		assert.match(any_order([
			{ start: src.at[1], end: src.at[2] },
			{ start: src.at[3], end: src.at[4] },
		]), map(highlights, (h) => h.range));
	});
});
