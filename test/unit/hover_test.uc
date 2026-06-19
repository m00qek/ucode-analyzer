import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { hover } from 'ucode_language_server.hover';

describe('hover', () => {
	afterEach(() => {
		documents.close('file:///test.uc');
	});

	it('returns markdown with node text and type for a named node', () => {
		documents.open('file:///test.uc', 'let x = 5;', 1);
		let doc = documents.get('file:///test.uc');

		// character 4 is 'x' → identifier node
		let result = hover(doc, { line: 0, character: 4 });

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
		assert.match(true, index(result.contents.value, 'x') >= 0);
		assert.match(true, index(result.contents.value, 'identifier') >= 0);
	});

	it('returns markdown with parent node when hovering anonymous token', () => {
		documents.open('file:///test.uc', 'let x = 5;', 1);
		let doc = documents.get('file:///test.uc');

		// character 0 is 'l' in 'let' keyword — anonymous, falls back to parent
		let result = hover(doc, { line: 0, character: 0 });

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
	});

	it('returns null when position is beyond end of file', () => {
		documents.open('file:///test.uc', 'let x = 5;', 1);
		let doc = documents.get('file:///test.uc');

		let result = hover(doc, { line: 99, character: 0 });

		assert.match(null, result);
	});
});
