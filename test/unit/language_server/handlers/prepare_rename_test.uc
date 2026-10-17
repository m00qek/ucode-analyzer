import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { prepareRename } from 'ucode_analyzer.language_server.handlers.prepare_rename';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

// Open the text of `src` (from cursors()) and prepare a rename at $0.
function prepareAt(src) {
	documents.open(URI, src.text, 1);
	return prepareRename(URI, documents.get(URI), src.at[0]);
}

afterEach(() => documents.close(URI));

describe('prepareRename', () => {
	it('returns null when cursor is not on an identifier', () => {
		// 'let' is an anonymous token
		assert.match(null, prepareAt(cursors("$0let x = 1;\n")));
	});

	it('returns null for position beyond end of file', () => {
		documents.open(URI, "let x = 1;\n", 1);
		assert.match(null, prepareRename(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('returns an object with range and placeholder', () => {
		let src = cursors("let $0$1x$2 = 1;\n");
		assert.match({ range: { start: src.at[1], end: src.at[2] }, placeholder: 'x' }, prepareAt(src));
	});

	it('placeholder matches the identifier text', () => {
		let result = prepareAt(cursors("let $0count = 0;\n"));
		assert.match('count', result.placeholder);
	});

	it('range covers the identifier token at the cursor', () => {
		let src = cursors("let $0$1count$2 = 0;\n");
		let result = prepareAt(src);
		assert.match({ start: src.at[1], end: src.at[2] }, result.range);
	});

	it('returns range of identifier when cursor is mid-token', () => {
		let src = cursors("let foo = 1;\n$1f$0oo$2;\n");
		let result = prepareAt(src);
		assert.match('foo', result.placeholder);
		assert.match({ start: src.at[1], end: src.at[2] }, result.range);
	});

	it('anchors on an identifier that appears only once', () => {
		let src = cursors("let $0$1unique$2 = 1;\n");
		assert.match({ range: { start: src.at[1], end: src.at[2] }, placeholder: 'unique' }, prepareAt(src));
	});
});
