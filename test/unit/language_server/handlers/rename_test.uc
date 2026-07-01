import { describe, it, assert, afterEach, beforeEach, mock } from 'utest';
import * as ts from 'tree_sitter';
import * as documents from 'code_analysis.documents';
import * as dag from 'code_analysis.dag.dag';
import { rename } from 'language_server.handlers.rename';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

let _dagCfg = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] } };

let URI   = 'file:///test.uc';
let URI_A = 'file:///app/src/a.uc';
let URI_B = 'file:///app/src/b.uc';

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

describe('cross-file rename', () => {
	let TEXT_A         = "export function foo() { foo(); }\n";
	let TEXT_B_NAMED   = "import { foo } from 'a';\nfoo();\n";
	let TEXT_B_ALIASED = "import { foo as bar } from 'a';\nbar();\n";
	let TEXT_B_NS      = "import * as a from 'a';\na.foo();\n";

	beforeEach(() => {
		dag.init(_dagCfg);
		dag.remove(URI_A);
		dag.remove(URI_B);
	});

	afterEach(() => {
		documents.close(URI_A);
		documents.close(URI_B);
		dag.remove(URI_A);
		dag.remove(URI_B);
	});

	function setupFiles(textA, textB) {
		dag.add(URI_A, textA, parse(textA));
		mock.global.patch('fs', { data: { '/app/src/a.uc': textA } });
		dag.add(URI_B, textB, parse(textB));
		mock.global.unpatch('fs');
		documents.open(URI_A, textA, 1);
		documents.open(URI_B, textB, 1);
	}

	it('named import: renames export in declaring file and import binding in importer', () => {
		setupFiles(TEXT_A, TEXT_B_NAMED);

		// cursor on 'foo' export in URI_A (line 0, char 16)
		let edit = rename(URI_A, documents.get(URI_A), { line: 0, character: 16 }, 'bar');

		// declaring file gets edits (export declaration + internal call)
		assert.match(true, length(edit.changes[URI_A]) >= 1);
		// importing file gets edits (import binding + call)
		assert.match(true, type(edit.changes[URI_B]) === 'array');
		assert.match(true, length(edit.changes[URI_B]) >= 1);
		for (let e in edit.changes[URI_B])
			assert.match('bar', e.newText);
	});

	it('named import: renaming from importer side updates both files', () => {
		setupFiles(TEXT_A, TEXT_B_NAMED);

		// cursor on 'foo' in 'foo();' on line 1 of URI_B
		let edit = rename(URI_B, documents.get(URI_B), { line: 1, character: 0 }, 'baz');

		assert.match(true, type(edit.changes[URI_A]) === 'array');
		assert.match(true, length(edit.changes[URI_A]) >= 1);
	});

	it('aliased import: renaming local alias stays within the importing file', () => {
		setupFiles(TEXT_A, TEXT_B_ALIASED);

		// cursor on 'bar' in 'bar();' on line 1 of URI_B (local alias, not remote name)
		let edit = rename(URI_B, documents.get(URI_B), { line: 1, character: 0 }, 'baz');

		// should NOT produce edits in URI_A
		assert.match(true, edit.changes[URI_A] === null);
	});

	it('aliased import: renaming export changes only the remote name in import specifier', () => {
		setupFiles(TEXT_A, TEXT_B_ALIASED);

		// cursor on 'foo' export in URI_A (line 0, char 16)
		let edit = rename(URI_A, documents.get(URI_A), { line: 0, character: 16 }, 'baz');

		// URI_B should have exactly 1 edit: the 'foo' in '{ foo as bar }', not 'bar' uses
		let editsB = edit.changes[URI_B];
		assert.match(true, type(editsB) === 'array');
		assert.match(1, length(editsB));
		assert.match('baz', editsB[0].newText);
	});

	it('aliased import in a mixed specifier list: renames only the remote name', () => {
		// `{ other, foo as bar }` — the leading non-aliased `other` used to make the
		// remote-name scan bail early and drop the `foo` rename edit entirely.
		let textA = "export function foo() { foo(); }\nexport function other() {}\n";
		let textB = "import { other, foo as bar } from 'a';\nbar(); other();\n";
		setupFiles(textA, textB);

		// cursor on 'foo' export in URI_A (line 0, char 16)
		let edit = rename(URI_A, documents.get(URI_A), { line: 0, character: 16 }, 'baz');

		let editsB = edit.changes[URI_B];
		assert.match(true, type(editsB) === 'array');
		assert.match(1, length(editsB));                 // just the remote `foo`
		assert.match('baz', editsB[0].newText);
	});

	it('namespace import: renaming export updates property accesses in namespace importer', () => {
		setupFiles(TEXT_A, TEXT_B_NS);

		// cursor on 'foo' export in URI_A (line 0, char 16)
		let edit = rename(URI_A, documents.get(URI_A), { line: 0, character: 16 }, 'qux');

		// URI_B uses 'a.foo()' — should get an edit on the 'foo' property
		let editsB = edit.changes[URI_B];
		assert.match(true, type(editsB) === 'array');
		assert.match(true, length(editsB) >= 1);
		assert.match('qux', editsB[0].newText);
	});
});
