import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { hover } from 'ucode_language_server.hover';
import { invalidateUri } from 'ucode_language_server.memo';

let URI = 'file:///test.uc';

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
});

describe('hover', () => {
	it('returns inferred type for an identifier', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 4 is 'x'; buildScope processes the declaration → x: int
		let result = hover(doc, { line: 0, character: 4 });

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
		assert.match(true, index(result.contents.value, 'x') >= 0);
		assert.match(true, index(result.contents.value, 'int') >= 0);
	});

	it('returns inferred type for an integer literal', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 8 is the '5' literal
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(true, index(result.contents.value, 'int') >= 0);
	});

	it('returns inferred type for a string literal', () => {
		documents.open(URI, "let s = 'hello';", 1);
		let doc = documents.get(URI);

		// character 8 is the opening quote of 'hello'
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(true, index(result.contents.value, 'string') >= 0);
	});

	it('returns null for an anonymous token with no inferable type', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 0 is 'l' in 'let'; nodeAtOffset returns lexical_declaration → unknown
		let result = hover(doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null when position is beyond end of file', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		assert.match(null, hover(doc, { line: 99, character: 0 }));
	});

	it('returns null for an unopened document when called through documents', () => {
		// doc.uri doesn't exist — simulate by closing before hover
		documents.open(URI, 'let x = 5;', 1);
		documents.close(URI);
		let doc = documents.get(URI);
		assert.match(null, doc);
	});
});
