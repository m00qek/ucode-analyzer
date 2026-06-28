import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { rename } from 'ucode_language_server.handlers.rename';

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
