import * as ts from 'tree_sitter';

// The nearest ancestor of `node` whose nodeType === type, or null.
export function findAncestor(node, type) {
	let p = ts.parent(node);
	while (p) {
		if (ts.nodeType(p) === type) return p;
		p = ts.parent(p);
	}
	return null;
};

// True for nodes whose named children are statements: a script's `program`, a
// template's `markup`, a `{ }` block, or an alt-syntax body.
export function isStatementList(nodeType) {
	return nodeType === 'program' || nodeType === 'markup' ||
	       nodeType === 'statement_block' || nodeType === 'statement_list';
};

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

// Return the text of the /** */ comment immediately before stmt among parent's
// children, or null. A // comment or any intervening named node resets the
// search — only an unbroken /** */ directly before stmt counts.
export function docBefore(stmt, parent, text) {
	let stmtStart = ts.startByte(stmt);
	let found = null;
	let children = ts.children(parent);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.startByte(c) >= stmtStart) break;
		if (ts.nodeType(c) === 'doc_comment')
			found = ts.text(c, text);
		else if (ts.isNamed(c))
			found = null;
	}
	return found;
};

// Like docBefore, but resolves the preceding /** */ doc for EVERY named child of
// parent in a single left-to-right pass, returning { startByte -> docText|null }.
// Callers needing docs for many siblings (object fields, top-level declarations)
// use this instead of calling docBefore per sibling — the latter re-fetches and
// re-scans the whole child list each time (O(siblings²); ~31ms on fw4.uc's
// 88-field return object). Same reset rule: a // comment or an intervening named
// node clears the pending doc.
export function docBeforeMap(parent, text) {
	let map = {};
	let pending = null;
	for (let c in ts.children(parent)) {
		let ct = ts.nodeType(c);
		if (ct === 'doc_comment') {
			pending = ts.text(c, text);
		} else if (ct === 'comment') {
			pending = null;
		} else if (ts.isNamed(c)) {
			map[ts.startByte(c)] = pending;
			pending = null;
		}
	}
	return map;
};

// The statement-level ancestor of `node` whose leading /** */ documents it, and
// that statement's enclosing block. Walks up until the parent is a statement
// list (isStatementList). Returns { target, parent } with parent=null when
// `node` has none.
export function docBearingStatement(node) {
	let target = node;
	let p = ts.parent(target);
	while (p) {
		let pt = ts.nodeType(p);
		if (isStatementList(pt)) break;
		target = p;
		p = ts.parent(target);
	}
	return { target, parent: p };
};

// The /** */ doc text immediately preceding `node`'s statement, or null. The
// inferrer has its own cached variant on the hot path; everything else uses this.
export function precedingDoc(node, text) {
	let s = docBearingStatement(node);
	return s.parent ? docBefore(s.target, s.parent, text) : null;
};

// Like docBefore, but returns the /** */ comment NODE (for its byte offsets)
// instead of its text. Same reset rule: a // comment or an intervening named
// node clears the pending doc.
export function docNodeBefore(stmt, parent, text) {
	let stmtStart = ts.startByte(stmt);
	let found = null;
	for (let c in ts.children(parent)) {
		if (ts.startByte(c) >= stmtStart) break;
		if (ts.nodeType(c) === 'doc_comment')
			found = c;
		else if (ts.isNamed(c))
			found = null;
	}
	return found;
};

// The /** */ comment NODE immediately preceding `node`'s statement, or null —
// the node counterpart of precedingDoc, for callers that need the comment's
// source position (e.g. to anchor a diagnostic inside the doc block).
export function precedingDocNode(node, text) {
	let s = docBearingStatement(node);
	return s.parent ? docNodeBefore(s.target, s.parent, text) : null;
};

// Build a table of byte offsets at which each line starts.
// lines[n] is the byte offset of the first byte on line n.
// One native split plus a per-line accumulation, rather than a per-byte
// substr scan — the latter was ~38ms on a 3400-line file (length() on a
// ucode string is a byte count, so the offsets stay byte-accurate).
export function buildLineTable(text) {
	let lines = [0];
	let parts = split(text, "\n");
	let off = 0;

	for (let i = 0; i < length(parts) - 1; i++) {
		off += length(parts[i]) + 1;   // +1 for the consumed '\n'
		push(lines, off);
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

// Byte offset → LSP { line, character } (character in UTF-16 units). An offset
// past the end of the text (a node of the closers mode.parse() may append)
// clamps to the end.
export function offsetToPosition(text, lineTable, offset) {
	offset = min(offset, length(text));
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

export function rangeOf(text, lineTable, node) {
	let start = offsetToPosition(text, lineTable, ts.startByte(node));
	let end   = offsetToPosition(text, lineTable, ts.endByte(node));
	return { start, end };
};
