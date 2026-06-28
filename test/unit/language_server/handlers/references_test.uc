import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { references } from 'language_server.handlers.references';

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

		assert.match(2, length(locs));
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

describe('references — scope awareness', () => {
	it('does not cross function-scope boundaries for parameters with the same name', () => {
		// Two functions both have a parameter called `x`.
		// References on function a's x must not include function b's x.
		let text = "function a(x) { return x; }\nfunction b(x) { return x; }\n";
		documents.open(URI, text, 1);

		// cursor on 'x' at (0, 11) — parameter in function a
		let locs = references(URI, documents.get(URI), { line: 0, character: 11 });

		// Only the declaration and use inside `a` — 2 total, not 4.
		assert.match(2, length(locs));
		for (let l in locs)
			assert.match(0, l.range.start.line);
	});

	it('does not mix outer and inner let bindings with the same name', () => {
		// Outer x and inner x (shadowed) are separate bindings.
		let text = "let x = 1;\nfunction foo() {\n  let x = 2;\n  return x;\n}\nx;\n";
		documents.open(URI, text, 1);

		// cursor on outer 'x' at (0, 4) — outer declaration
		let outer = references(URI, documents.get(URI), { line: 0, character: 4 });
		// cursor on inner 'x' at (2, 6) — inner declaration
		let inner = references(URI, documents.get(URI), { line: 2, character: 6 });

		// Outer x: declaration (line 0) + reference (line 5) = 2
		assert.match(2, length(outer));
		// Inner x: declaration (line 2) + reference (line 3) = 2
		assert.match(2, length(inner));
	});

	it('finds all occurrences of a for-in loop variable within its body', () => {
		let text = "let arr = [];\nfor (let i in arr) {\n  i;\n  i;\n}\n";
		documents.open(URI, text, 1);

		// cursor on 'i' in the loop body (line 2, char 2)
		let locs = references(URI, documents.get(URI), { line: 2, character: 2 });

		// declaration (for-in variable) + 2 uses = 3
		assert.match(3, length(locs));
	});

	it('finds both the declaration and use of a catch variable', () => {
		let text = "try {\n} catch(e) {\n  e;\n}\n";
		documents.open(URI, text, 1);

		// cursor on 'e' inside catch body (line 2, char 2)
		let locs = references(URI, documents.get(URI), { line: 2, character: 2 });

		// catch parameter declaration + use = 2
		assert.match(2, length(locs));
	});
});
