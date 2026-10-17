import { describe, it, assert } from 'utest';
import { cursors, locate } from 'cursor';

describe('cursor markers', () => {
	it('strips the markers and gives their positions and offsets', () => {
		let src = cursors("let $1count = 0;\n$0count;");
		assert.match("let count = 0;\ncount;", src.text);
		assert.match({ line: 1, character: 0 }, src.at[0]);
		assert.match({ line: 0, character: 4 }, src.at[1]);
		assert.match([15, 4], src.offset);
	});

	it('counts columns in UTF-16 units', () => {
		let src = cursors("let s = 'é😀'; $0s;");
		assert.match({ line: 0, character: 15 }, src.at[0]);
		assert.match(18, src.offset[0]);
	});

	it('leaves a $ that is not followed by a digit', () => {
		assert.match('`${x}` $', cursors('`${x}` $').text);
	});

	it('rejects a marker used twice', () => {
		assert.throws(() => cursors('$0a$0'));
	});

	it('locates the nth occurrence of a needle', () => {
		let text = "a\nfoo bar\nfoo";
		assert.match({ line: 1, character: 0 }, locate(text, 'foo'));
		assert.match({ line: 2, character: 0 }, locate(text, 'foo', 1));
		assert.match({ line: 1, character: 4 }, locate(text, 'foo bar', 0, 4));
		assert.throws(() => locate(text, 'baz'));
	});
});
