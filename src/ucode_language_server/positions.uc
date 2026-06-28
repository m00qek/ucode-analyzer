import * as ts from 'tree_sitter';

// Walk to the deepest named node that contains offset.
export function nodeAtOffset(node, offset) {
	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let child = ts.namedChild(node, i);
		if (ts.startByte(child) <= offset && offset < ts.endByte(child))
			return nodeAtOffset(child, offset);
	}
	return node;
};

// Build a table of byte offsets at which each line starts.
// lines[n] is the byte offset of the first byte on line n.
export function buildLineTable(text) {
	let lines = [0];
	let len = length(text);

	for (let i = 0; i < len; i++) {
		if (substr(text, i, 1) === '\n')
			push(lines, i + 1);
	}

	return lines;
};

// Returns the byte length of the UTF-8 sequence whose first byte is b0.
function utf8Len(b0) {
	if (b0 < 0x80) return 1;
	if (b0 < 0xE0) return 2;
	if (b0 < 0xF0) return 3;
	return 4;
};

// Decodes the UTF-8 codepoint starting at byte offset i in text.
function utf8Cp(text, i) {
	let b0 = ord(substr(text, i, 1));

	if (b0 < 0x80)
		return b0;

	let b1 = ord(substr(text, i + 1, 1));

	if (b0 < 0xE0)
		return ((b0 & 0x1F) << 6) | (b1 & 0x3F);

	let b2 = ord(substr(text, i + 2, 1));

	if (b0 < 0xF0)
		return ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);

	let b3 = ord(substr(text, i + 3, 1));
	return ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
};

// LSP { line, character } (character in UTF-16 units) → byte offset.
export function positionToOffset(text, lineTable, position) {
	let i = lineTable[position.line] ?? length(text);
	let units = position.character;

	while (units > 0 && i < length(text)) {
		let b0 = ord(substr(text, i, 1));
		let cp = utf8Cp(text, i);
		units -= cp > 0xFFFF ? 2 : 1;
		i += utf8Len(b0);
	}

	return i;
};

// Byte offset → LSP { line, character } (character in UTF-16 units).
export function offsetToPosition(text, lineTable, offset) {
	let lo = 0;
	let hi = length(lineTable) - 1;

	while (lo < hi) {
		let mid = int((lo + hi + 1) / 2);
		if (lineTable[mid] <= offset)
			lo = mid;
		else
			hi = mid - 1;
	}

	let line = lo;
	let character = 0;
	let i = lineTable[line];

	while (i < offset) {
		let b0 = ord(substr(text, i, 1));
		character += utf8Cp(text, i) > 0xFFFF ? 2 : 1;
		i += utf8Len(b0);
	}

	return { line, character };
};
