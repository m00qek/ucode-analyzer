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
		let highlights = highlightAt(cursors("let $0z = 0;\nz;\nz;\n"));
		assert.match(3, length(highlights));
	});

	it('each highlight has kind 1 (Text)', () => {
		let highlights = highlightAt(cursors("let $0x = 1;\nx;\n"));
		for (let h in highlights)
			assert.match(1, h.kind);
	});

	it('highlight ranges span the exact identifier token', () => {
		let src = cursors("let $0$1count$2 = 0;\n");
		let highlights = highlightAt(src);
		assert.match({ start: src.at[1], end: src.at[2] }, highlights[0].range);
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
