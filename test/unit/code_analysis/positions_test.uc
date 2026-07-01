import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import * as pos from 'code_analysis.positions';

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

describe('positions (nodeAtOffset)', () => {
	let _p = ts.newParser(ts.ucode());

	function parse(text) { return ts.parse(_p, text); }

	// 'let foo = 1;' — 'foo' is at bytes 4–6
	it('drills to the identifier node', () => {
		let text = 'let foo = 1;';
		let root = ts.rootNode(parse(text));
		assert.match('identifier', ts.nodeType(pos.nodeAtOffset(root, 4)));
	});

	// 'let x = 42;' — '42' starts at byte 8
	it('drills to the number node', () => {
		let text = 'let x = 42;';
		let root = ts.rootNode(parse(text));
		assert.match('number', ts.nodeType(pos.nodeAtOffset(root, 8)));
	});

	it('returns the given node when no named child contains offset', () => {
		let text = 'let x = 1;';
		let root = ts.rootNode(parse(text));
		// offset past end of file — no child matches, returns root itself
		assert.match('program', ts.nodeType(pos.nodeAtOffset(root, 999)));
	});
});

describe('positions (docBefore)', () => {
	let _p = ts.newParser(ts.ucode());

	function parse(text) { return ts.parse(_p, text); }
	function root(text) { return ts.rootNode(parse(text)); }

	// Find the first named child with the given node type.
	// Safer than index arithmetic because comment nodes are named in
	// tree-sitter-ucode, so namedChild(r, 0) may be the comment, not the stmt.
	function findChild(parent, nodeType) {
		let children = ts.namedChildren(parent);
		for (let i = 0; i < length(children); i++)
			if (ts.nodeType(children[i]) === nodeType) return children[i];
		return null;
	}

	function findChildren(parent, nodeType) {
		let result = [];
		let children = ts.namedChildren(parent);
		for (let i = 0; i < length(children); i++)
			if (ts.nodeType(children[i]) === nodeType) push(result, children[i]);
		return result;
	}

	it('returns null when no comment precedes the statement', () => {
		let text = 'export function foo() {};';
		let r = root(text);
		assert.match(null, pos.docBefore(findChild(r, 'export_statement'), r, text));
	});

	it('returns the /** */ text immediately before the statement', () => {
		let text = '/** doc */\nexport function foo() {};';
		let r = root(text);
		assert.match('/** doc */', pos.docBefore(findChild(r, 'export_statement'), r, text));
	});

	it('returns null for a // line comment — only /** */ counts', () => {
		let text = '// not jsdoc\nexport function foo() {};';
		let r = root(text);
		assert.match(null, pos.docBefore(findChild(r, 'export_statement'), r, text));
	});

	it('resets when a named node intervenes between /** */ and statement', () => {
		let text = '/** doc */\nexport function a() {};\nexport function b() {};';
		let r = root(text);
		let stmts = findChildren(r, 'export_statement');
		assert.match(null, pos.docBefore(stmts[1], r, text));
	});

	it('picks the last /** */ when two appear consecutively', () => {
		let text = '/** first */\n/** second */\nexport function foo() {};';
		let r = root(text);
		assert.match('/** second */', pos.docBefore(findChild(r, 'export_statement'), r, text));
	});

	it('works for a pair inside an object literal (non-root parent)', () => {
		let text = 'export const ns = { /** greet */ greet: function() {} };';
		let r = root(text);
		let expStmt = findChild(r, 'export_statement');
		let lexDecl = ts.namedChild(expStmt, 0);
		let varDecl = ts.namedChild(lexDecl, 0);
		let objNode = ts.childByField(varDecl, 'value');
		let pair    = findChild(objNode, 'pair');
		let docTxt  = pos.docBefore(pair, objNode, text);
		assert.match(true, docTxt !== null && index(docTxt, 'greet') >= 0);
	});
});
