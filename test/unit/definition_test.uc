import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { definition } from 'ucode_language_server.definition';

let URI = 'file:///test.uc';

afterEach(() => {
	documents.close(URI);
});

describe('definition — local declarations', () => {
	it('finds a let declaration by name', () => {
		let text = "let count = 0;\ncount;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// position (1, 0) is 'count' on the second line (the reference)
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);       // declaration is on line 0
		assert.match(4, result.range.start.character);  // 'count' starts at col 4
	});

	it('finds a const declaration', () => {
		let text = "const MAX = 100;\nMAX;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(6, result.range.start.character);  // 'MAX' starts at col 6
	});

	it('finds a function declaration', () => {
		let text = "function greet() {}\ngreet;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(9, result.range.start.character);  // 'greet' after 'function '
	});

	it('finds an exported let declaration', () => {
		let text = "export let x = 1;\nx;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
	});

	it('returns null for an unknown identifier', () => {
		let text = "foo;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null when cursor is on a non-identifier node', () => {
		let text = "let x = 5;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// position (0, 0) is 'l' in 'let' — anonymous token
		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 5;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		assert.match(null, definition(URI, doc, { line: 99, character: 0 }));
	});
});
