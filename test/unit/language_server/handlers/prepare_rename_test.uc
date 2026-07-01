import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { prepareRename } from 'language_server.handlers.prepare_rename';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('prepareRename', () => {
	it('returns null when cursor is not on an identifier', () => {
		documents.open(URI, "let x = 1;\n", 1);
		// 'l' in 'let' — anonymous token
		assert.match(null, prepareRename(URI, documents.get(URI), { line: 0, character: 0 }));
	});

	it('returns null for position beyond end of file', () => {
		documents.open(URI, "let x = 1;\n", 1);
		assert.match(null, prepareRename(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('returns an object with range and placeholder', () => {
		documents.open(URI, "let x = 1;\n", 1);
		let result = prepareRename(URI, documents.get(URI), { line: 0, character: 4 });
		assert.match(true, result !== null);
		assert.match(true, type(result.range) === 'object');
		assert.match(true, type(result.placeholder) === 'string');
	});

	it('placeholder matches the identifier text', () => {
		documents.open(URI, "let count = 0;\n", 1);
		let result = prepareRename(URI, documents.get(URI), { line: 0, character: 4 });
		assert.match('count', result.placeholder);
	});

	it('range covers the identifier token at the cursor', () => {
		documents.open(URI, "let count = 0;\n", 1);
		let result = prepareRename(URI, documents.get(URI), { line: 0, character: 4 });
		// 'count' starts at col 4, ends at col 9
		assert.match(0, result.range.start.line);
		assert.match(4, result.range.start.character);
		assert.match(0, result.range.end.line);
		assert.match(9, result.range.end.character);
	});

	it('returns range of identifier when cursor is mid-token', () => {
		documents.open(URI, "let foo = 1;\nfoo;\n", 1);
		// cursor in the middle of 'foo' on line 1
		let result = prepareRename(URI, documents.get(URI), { line: 1, character: 1 });
		assert.match('foo', result.placeholder);
		assert.match(1, result.range.start.line);
		assert.match(0, result.range.start.character);
	});

	it('returns null for unique identifier with no references (only declaration)', () => {
		// A unique identifier that appears only once still has a valid anchor
		documents.open(URI, "let unique = 1;\nunique;\n", 1);
		let result = prepareRename(URI, documents.get(URI), { line: 0, character: 4 });
		assert.match(true, result !== null);
		assert.match('unique', result.placeholder);
	});
});
