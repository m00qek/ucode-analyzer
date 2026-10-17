// Cursor markers, so a test says where it points instead of counting columns.
//
//   let src = cursors("let $1count = 0;\n$0count;");
//   definition(URI, doc, src.at[0]);              // { line: 1, character: 0 }
//   assert.match(src.at[1], result.range.start);  // { line: 0, character: 4 }
//
// `$0` … `$9` mark positions in the text: src.text is the text without them,
// src.at[n] the LSP position of `$n` (UTF-16 columns) and src.offset[n] its
// byte offset.
export function cursors(marked) {
	let text = '', at = [], offset = [];
	let line = 0, character = 0;
	for (let i = 0; i < length(marked); i++) {
		let c = substr(marked, i, 1);
		let d = substr(marked, i + 1, 1);
		if (c === '$' && length(d) && index('0123456789', d) >= 0) {
			let n = +d;
			if (at[n]) die(sprintf('cursor marker $%d appears twice', n));
			at[n] = { line, character };
			offset[n] = length(text);
			i++;
			continue;
		}
		text += c;
		let b = ord(c);
		if (c === "\n") {
			line++;
			character = 0;
		} else if (b < 0x80 || b >= 0xC0) {   // not a UTF-8 continuation byte
			character += (b >= 0xF0) ? 2 : 1;  // astral characters are surrogate pairs
		}
	}
	return { text, at, offset };
};

// The LSP position of the nth (default 0) occurrence of needle in text, plus
// `shift` bytes (default 0) — for pointing into a file read from disk.
export function locate(text, needle, nth, shift) {
	let from = 0, at = -1;
	for (let k = 0; k <= (nth ?? 0); k++) {
		at = index(substr(text, from), needle);
		if (at < 0) die(sprintf('locate: %J not found (occurrence %d)', needle, k));
		at += from;
		from = at + 1;
	}
	let src = cursors(substr(text, 0, at + (shift ?? 0)) + '$0');
	return src.at[0];
};
