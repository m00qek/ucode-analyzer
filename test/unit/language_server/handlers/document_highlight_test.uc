import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { documentHighlight } from 'language_server.handlers.document_highlight';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('documentHighlight', () => {
	it('returns null when cursor is not on an identifier', () => {
		documents.open(URI, "let x = 1;\n", 1);
		// 'l' in 'let' — anonymous token
		assert.match(null, documentHighlight(URI, documents.get(URI), { line: 0, character: 0 }));
	});

	it('returns null for position beyond end of file', () => {
		documents.open(URI, "let x = 1;\n", 1);
		assert.match(null, documentHighlight(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('returns all occurrences as highlights', () => {
		documents.open(URI, "let z = 0;\nz;\nz;\n", 1);
		let highlights = documentHighlight(URI, documents.get(URI), { line: 0, character: 4 });
		assert.match(3, length(highlights));
	});

	it('each highlight has kind 1 (Text)', () => {
		documents.open(URI, "let x = 1;\nx;\n", 1);
		let highlights = documentHighlight(URI, documents.get(URI), { line: 0, character: 4 });
		for (let h in highlights)
			assert.match(1, h.kind);
	});

	it('highlight ranges span the exact identifier token', () => {
		documents.open(URI, "let count = 0;\n", 1);
		let highlights = documentHighlight(URI, documents.get(URI), { line: 0, character: 4 });
		let h = highlights[0];
		// 'count' starts at col 4 and ends at col 9
		assert.match(0, h.range.start.line);
		assert.match(4, h.range.start.character);
		assert.match(0, h.range.end.line);
		assert.match(9, h.range.end.character);
	});

	it('is scope-aware: does not cross function boundaries', () => {
		let text = "function a(x) { return x; }\nfunction b(x) { return x; }\n";
		documents.open(URI, text, 1);
		// cursor on 'x' parameter in function a
		let highlights = documentHighlight(URI, documents.get(URI), { line: 0, character: 11 });
		// Only 2: parameter declaration + use inside a
		assert.match(2, length(highlights));
		for (let h in highlights)
			assert.match(0, h.range.start.line);
	});
});
