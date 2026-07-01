import * as ts from 'tree_sitter';

// The content of a string literal node — the concatenated text of its
// string_fragment children, without the surrounding quotes. An empty literal
// ('' / "") has no fragment child and yields "".
//
// Escape sequences are NOT decoded: a string_fragment is the raw text between
// escapes, so `"a\nb"` yields "ab" (the escape byte is dropped, not turned into
// a newline). Every caller here wants identifier-like content — module
// specifiers, member/key names — where escapes do not occur in practice.
// Escape-aware scanning (format specifiers) lives in format_string.uc.
export function stringLiteralText(node, source) {
	let out = '';
	for (let k = 0; k < ts.childCount(node); k++) {
		let ch = ts.child(node, k);
		if (ts.nodeType(ch) === 'string_fragment')
			out += ts.text(ch, source);
	}
	return out;
};
