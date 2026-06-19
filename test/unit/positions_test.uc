import { describe, it, assert } from 'utest';
import * as pos from 'ucode_language_server.positions';

describe('positions (buildLineTable)', () => {
	it('single line', () => {
		assert.match([0], pos.buildLineTable('hello'));
	});

	it('multiple lines', () => {
		assert.match([0, 2, 4], pos.buildLineTable('a\nb\nc'));
	});

	it('trailing newline', () => {
		assert.match([0, 2, 4], pos.buildLineTable('a\nb\n'));
	});

	it('empty string', () => {
		assert.match([0], pos.buildLineTable(''));
	});
});

describe('positions (ASCII)', () => {
	let text = 'hello\nworld';
	let lt = pos.buildLineTable(text);

	it('positionToOffset line 0', () => {
		assert.match(0, pos.positionToOffset(text, lt, { line: 0, character: 0 }));
		assert.match(3, pos.positionToOffset(text, lt, { line: 0, character: 3 }));
	});

	it('positionToOffset line 1', () => {
		assert.match(6, pos.positionToOffset(text, lt, { line: 1, character: 0 }));
		assert.match(8, pos.positionToOffset(text, lt, { line: 1, character: 2 }));
	});

	it('offsetToPosition line 0', () => {
		assert.match({ line: 0, character: 0 }, pos.offsetToPosition(text, lt, 0));
		assert.match({ line: 0, character: 3 }, pos.offsetToPosition(text, lt, 3));
	});

	it('offsetToPosition line 1', () => {
		assert.match({ line: 1, character: 0 }, pos.offsetToPosition(text, lt, 6));
		assert.match({ line: 1, character: 2 }, pos.offsetToPosition(text, lt, 8));
	});

	it('round-trips every byte offset', () => {
		for (let offset = 0; offset <= length(text); offset++) {
			// skip mid-sequence bytes (none in ASCII, but guard for completeness)
			let p = pos.offsetToPosition(text, lt, offset);
			assert.match(offset, pos.positionToOffset(text, lt, p));
		}
	});
});

describe('positions (multibyte UTF-8)', () => {
	it('2-byte sequence counts as 1 UTF-16 unit', () => {
		// é = U+00E9 = \xC3\xA9 (2 bytes, 1 UTF-16 unit)
		let text = '\xC3\xA9x';
		let lt = pos.buildLineTable(text);
		assert.match(2, pos.positionToOffset(text, lt, { line: 0, character: 1 }));
		assert.match({ line: 0, character: 1 }, pos.offsetToPosition(text, lt, 2));
	});

	it('3-byte sequence counts as 1 UTF-16 unit', () => {
		// € = U+20AC = \xE2\x82\xAC (3 bytes, 1 UTF-16 unit)
		let text = '\xE2\x82\xACx';
		let lt = pos.buildLineTable(text);
		assert.match(3, pos.positionToOffset(text, lt, { line: 0, character: 1 }));
		assert.match({ line: 0, character: 1 }, pos.offsetToPosition(text, lt, 3));
	});

	it('4-byte sequence counts as 2 UTF-16 units', () => {
		// 😀 = U+1F600 = \xF0\x9F\x98\x80 (4 bytes, 2 UTF-16 units)
		let text = '\xF0\x9F\x98\x80x';
		let lt = pos.buildLineTable(text);
		assert.match(4, pos.positionToOffset(text, lt, { line: 0, character: 2 }));
		assert.match({ line: 0, character: 2 }, pos.offsetToPosition(text, lt, 4));
	});

	it('round-trips all character-boundary offsets in mixed multibyte text', () => {
		// 'a' + é (2 bytes) + '\n' + € (3 bytes) + 😀 (4 bytes) + 'b'
		let text = 'a\xC3\xA9\n\xE2\x82\xAC\xF0\x9F\x98\x80b';
		let lt = pos.buildLineTable(text);

		for (let off = 0; off <= length(text); off++) {
			// Skip UTF-8 continuation bytes (0x80–0xBF) — not valid start positions.
			if (off < length(text)) {
				let b = ord(substr(text, off, 1));
				if (b >= 0x80 && b < 0xC0)
					continue;
			}

			let p = pos.offsetToPosition(text, lt, off);
			assert.match(off, pos.positionToOffset(text, lt, p));
		}
	});
});
