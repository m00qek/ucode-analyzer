import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { rename } from 'language_server.handlers.rename';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('rename', () => {
	it('returns null when cursor is not on an identifier', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		// 'l' in 'let' — anonymous token
		assert.match(null, rename(URI, documents.get(URI), { line: 0, character: 0 }, 'y'));
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		assert.match(null, rename(URI, documents.get(URI), { line: 99, character: 0 }, 'y'));
	});

	it('returns WorkspaceEdit with changes for the current uri', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		let edit = rename(URI, documents.get(URI), { line: 0, character: 4 }, 'y');

		assert.match(true, edit !== null);
		assert.match(true, edit.changes !== null);
		assert.match(true, edit.changes[URI] !== null);
	});

	it('produces one edit per occurrence', () => {
		let text = "let x = 1;\nlet y = x + x;\n";
		documents.open(URI, text, 1);

		let edit = rename(URI, documents.get(URI), { line: 0, character: 4 }, 'z');

		// x appears 3 times
		assert.match(3, length(edit.changes[URI]));
	});

	it('each edit has newText set to the new name', () => {
		let text = "let x = x;\n";
		documents.open(URI, text, 1);

		let edit = rename(URI, documents.get(URI), { line: 0, character: 4 }, 'renamed');
		let edits = edit.changes[URI];

		assert.match(2, length(edits));
		for (let e in edits)
			assert.match('renamed', e.newText);
	});

	it('edit ranges span the exact identifier token', () => {
		let text = "let count = 0;\n";
		documents.open(URI, text, 1);

		let edit = rename(URI, documents.get(URI), { line: 0, character: 4 }, 'total');
		let e = edit.changes[URI][0];

		// 'count' starts at col 4 and ends at col 9
		assert.match(0,  e.range.start.line);
		assert.match(4,  e.range.start.character);
		assert.match(0,  e.range.end.line);
		assert.match(9,  e.range.end.character);
	});
});

describe('rename — scope awareness', () => {
	it('renames only the binding in the correct scope, not shadowed names', () => {
		// Two functions both named parameter `val`.  Renaming one must not touch the other.
		let text = "function a(val) { return val; }\nfunction b(val) { return val; }\n";
		documents.open(URI, text, 1);

		// cursor on `val` in function a (line 0, char 11)
		let edit = rename(URI, documents.get(URI), { line: 0, character: 11 }, 'value');

		let edits = edit.changes[URI];
		// Only 2 edits: the parameter declaration and its use inside `a`.
		assert.match(2, length(edits));
		// All edits are on line 0 (inside function a).
		for (let e in edits)
			assert.match(0, e.range.start.line);
	});

	it('renames a shadowing inner binding without touching the outer binding', () => {
		let text = "let n = 1;\nfunction foo() {\n  let n = 2;\n  return n;\n}\n";
		documents.open(URI, text, 1);

		// cursor on inner `n` (line 2, char 6) — the one inside foo()
		let edit = rename(URI, documents.get(URI), { line: 2, character: 6 }, 'm');

		let edits = edit.changes[URI];
		// Only 2 edits: inner declaration + inner use. NOT the outer `n`.
		assert.match(2, length(edits));
		for (let e in edits)
			assert.match(true, e.range.start.line >= 2);
	});
});
