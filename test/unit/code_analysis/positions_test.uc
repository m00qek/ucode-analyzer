import { describe, it, assert, prop, gen } from 'utest';
import * as ts from 'tree_sitter';
import * as pos from 'ucode_analyzer.code_analysis.positions';
import { cursors } from 'cursor';

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

	it('drills to the identifier node', () => {
		let src = cursors('let $0foo = 1;');
		let root = ts.rootNode(parse(src.text));
		assert.match('identifier', ts.nodeType(pos.nodeAtOffset(root, src.offset[0])));
	});

	it('drills to the number node', () => {
		let src = cursors('let x = $042;');
		let root = ts.rootNode(parse(src.text));
		assert.match('number', ts.nodeType(pos.nodeAtOffset(root, src.offset[0])));
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
		assert.match('/** greet */', docTxt);
	});
});

// ---------------------------------------------------------------------------
// Property-based tests: byte <-> LSP position round-trips over multi-byte and
// astral UTF-8, and buildLineTable invariants.
// ---------------------------------------------------------------------------

// Text fragments spanning every UTF-8 length class plus a newline. The comment
// records (byte length, UTF-16 units) so the invariants below stay readable:
//   'a' 'Z' ' '  -> 1 byte,  1 unit  (ASCII)
//   '\n'         -> 1 byte,  1 unit  (line break)
//   'é'          -> 2 bytes, 1 unit  (U+00E9)
//   '€'          -> 3 bytes, 1 unit  (U+20AC)
//   '😀'         -> 4 bytes, 2 units (U+1F600, astral / surrogate pair)
let PIECES = ['a', "\n", 'é', '€', '😀', 'Z', ' '];

// Concatenate the chosen pieces and record the byte offset of every character
// boundary (including 0 and end-of-text).
function buildText(idxs) {
	let text = '';
	let boundaries = [0];
	for (let k in idxs) {
		text += PIECES[k];
		push(boundaries, length(text));
	}
	return { text, boundaries };
}

describe('positions (precedingDoc)', () => {
	let _p = ts.newParser(ts.markup());

	it('finds the doc of a function declared at a template\'s top level', () => {
		let text = "{% /** Says hi. */\nfunction f() { return 1; } %}";
		let r = ts.rootNode(ts.parse(_p, text));
		let name = pos.nodeAtOffset(r, index(text, 'f()'));
		assert.match('/** Says hi. */', pos.precedingDoc(name, text));
	});
});

describe('positions — properties', () => {
	prop('offset -> position -> offset is identity at every character boundary',
		gen.array(gen.int(0, length(PIECES) - 1), { max_len: 14 }),
		(idxs, ctx) => {
			let b = buildText(idxs);
			ctx.classify('empty', length(b.text) === 0);
			ctx.classify('has-astral', index(b.text, '😀') >= 0);
			ctx.classify('multiline', index(b.text, "\n") >= 0);
			let lt = pos.buildLineTable(b.text);
			for (let off in b.boundaries) {
				let p = pos.offsetToPosition(b.text, lt, off);
				let back = pos.positionToOffset(b.text, lt, p);
				assert.match(off, back,
					sprintf('round-trip broke at byte %d (line %d, char %d)',
						off, p.line, p.character));
			}
		});

	prop('offsetToPosition is monotonic non-decreasing across boundaries',
		gen.array(gen.int(0, length(PIECES) - 1), { max_len: 14 }),
		(idxs) => {
			let b = buildText(idxs);
			let lt = pos.buildLineTable(b.text);
			let prev = pos.offsetToPosition(b.text, lt, b.boundaries[0]);
			for (let i = 1; i < length(b.boundaries); i++) {
				let cur = pos.offsetToPosition(b.text, lt, b.boundaries[i]);
				let advanced = cur.line > prev.line ||
					(cur.line === prev.line && cur.character >= prev.character);
				assert.match(true, advanced,
					sprintf('position went backwards at byte %d', b.boundaries[i]));
				prev = cur;
			}
		});

	prop('buildLineTable: starts at 0, strictly increasing, one entry per line',
		gen.array(gen.int(0, length(PIECES) - 1), { max_len: 14 }),
		(idxs, ctx) => {
			let b = buildText(idxs);
			let lt = pos.buildLineTable(b.text);

			// Independently compute the byte offsets of every line start.
			let expected = [0];
			for (let i = 0; i < length(b.text); i++)
				if (substr(b.text, i, 1) === "\n") push(expected, i + 1);

			let newlines = length(expected) - 1;
			ctx.classify('multiline', newlines > 0);

			assert.match(0, lt[0]);
			assert.match(newlines + 1, length(lt));   // one line start per newline, plus the first
			for (let i = 1; i < length(lt); i++)
				assert.match(true, lt[i] > lt[i - 1], 'line starts must strictly increase');
			assert.match(expected, lt);               // byte-accurate against the scan
		});
});
