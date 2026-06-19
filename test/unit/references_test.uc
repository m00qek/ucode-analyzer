import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { references } from 'ucode_language_server.references';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('references', () => {
	it('returns null when cursor is not on an identifier', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		// position on 'l' in 'let' — anonymous token
		assert.match(null, references(URI, documents.get(URI), { line: 0, character: 0 }));
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		assert.match(null, references(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('finds all occurrences of an identifier', () => {
		let text = "let x = 1;\nlet y = x + x;\n";
		documents.open(URI, text, 1);

		// cursor on 'x' at (0, 4) — declaration
		let locs = references(URI, documents.get(URI), { line: 0, character: 4 });

		// x appears 3 times: declaration + two uses
		assert.match(3, length(locs));
	});

	it('each location has the correct uri', () => {
		let text = "let z = 0;\nz;\n";
		documents.open(URI, text, 1);

		let locs = references(URI, documents.get(URI), { line: 0, character: 4 });

		for (let l in locs)
			assert.match(URI, l.uri);
	});

	it('locations are on the correct lines', () => {
		let text = "let v = 1;\nv;\nv;\n";
		documents.open(URI, text, 1);

		let locs = references(URI, documents.get(URI), { line: 0, character: 4 });

		assert.match(3, length(locs));
		let lines = sort(map(locs, (l) => l.range.start.line));
		assert.match(0, lines[0]);
		assert.match(1, lines[1]);
		assert.match(2, lines[2]);
	});

	it('finds single occurrence when identifier appears only once', () => {
		let text = "unique;\n";
		documents.open(URI, text, 1);

		let locs = references(URI, documents.get(URI), { line: 0, character: 0 });

		assert.match(1, length(locs));
	});
});
