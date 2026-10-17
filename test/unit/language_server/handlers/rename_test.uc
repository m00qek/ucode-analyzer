import { describe, it, assert, afterEach, beforeEach, mock, any_order } from 'utest';
import * as ts from 'tree_sitter';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { rename } from 'ucode_analyzer.language_server.handlers.rename';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

let URI   = 'file:///test.uc';
let URI_A = fixture.uri('a.uc');
let URI_B = fixture.uri('b.uc');

// Open the text of `src` (from cursors()) and rename the name at $0.
function renameAt(src, newName) {
	documents.open(URI, src.text, 1);
	return rename(URI, documents.get(URI), src.at[0], newName);
}

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

function ranges(edits) {
	return map(edits, (e) => e.range);
}

afterEach(() => documents.close(URI));

describe('rename', () => {
	it('returns null when cursor is not on an identifier', () => {
		// 'let' is an anonymous token
		assert.match(null, renameAt(cursors("$0let x = 1;\n"), 'y'));
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		assert.match(null, rename(URI, documents.get(URI), { line: 99, character: 0 }, 'y'));
	});

	it('returns WorkspaceEdit with changes for the current uri', () => {
		let edit = renameAt(cursors("let $0x = 1;\n"), 'y');

		assert.match(true, edit !== null);
		assert.match(true, edit.changes !== null);
		assert.match(true, edit.changes[URI] !== null);
	});

	it('produces one edit per occurrence', () => {
		let edit = renameAt(cursors("let $0x = 1;\nlet y = x + x;\n"), 'z');

		// x appears 3 times
		assert.match(3, length(edit.changes[URI]));
	});

	it('each edit has newText set to the new name', () => {
		let edit = renameAt(cursors("let $0x = x;\n"), 'renamed');
		let edits = edit.changes[URI];

		assert.match(2, length(edits));
		for (let e in edits)
			assert.match('renamed', e.newText);
	});

	it('edit ranges span the exact identifier token', () => {
		let src = cursors("let $0$1count$2 = 0;\n");
		let edit = renameAt(src, 'total');

		assert.match(span(src, 1, 2), edit.changes[URI][0].range);
	});
});

describe('rename — scope awareness', () => {
	it('renames only the binding in the correct scope, not shadowed names', () => {
		// Two functions both named parameter `val`.  Renaming one must not touch the other.
		let src = cursors("function a($0$1val$2) { return $3val$4; }\nfunction b(val) { return val; }\n");
		let edit = renameAt(src, 'value');

		// Only 2 edits: the parameter declaration and its use inside `a`.
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(edit.changes[URI]));
	});

	it('renames a shadowing inner binding without touching the outer binding', () => {
		// on the inner `n`, the one inside foo()
		let src = cursors("let n = 1;\nfunction foo() {\n  let $0$1n$2 = 2;\n  return $3n$4;\n}\n");
		let edit = renameAt(src, 'm');

		// Only 2 edits: inner declaration + inner use. NOT the outer `n`.
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(edit.changes[URI]));
	});
});

describe('cross-file rename', () => {
	let TEXT_A         = cursors("export function $0foo() { foo(); };\n");
	let TEXT_B_NAMED   = cursors("import { foo } from 'a';\n$0foo();\n");
	let TEXT_B_ALIASED = cursors("import { $1foo$2 as bar } from 'a';\n$0bar();\n");
	let TEXT_B_NS      = cursors("import * as a from 'a';\na.foo();\n");

	beforeEach(() => {
		dag.init(fixture.config());
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
		mock.global.patch('fs', { data: { [fixture.WORKSPACE + '/a.uc']: textA } });
		dag.add(URI_B, textB, parse(textB));
		mock.global.unpatch('fs');
		documents.open(URI_A, textA, 1);
		documents.open(URI_B, textB, 1);
	}

	it('named import: renames export in declaring file and import binding in importer', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the 'foo' export
		let edit = rename(URI_A, documents.get(URI_A), TEXT_A.at[0], 'bar');

		// declaring file gets edits (export declaration + internal call)
		assert.match(true, length(edit.changes[URI_A]) >= 1);
		// importing file gets edits (import binding + call)
		assert.match(true, type(edit.changes[URI_B]) === 'array');
		assert.match(true, length(edit.changes[URI_B]) >= 1);
		for (let e in edit.changes[URI_B])
			assert.match('bar', e.newText);
	});

	it('named import: renaming from importer side updates both files', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the call 'foo();'
		let edit = rename(URI_B, documents.get(URI_B), TEXT_B_NAMED.at[0], 'baz');

		assert.match(true, type(edit.changes[URI_A]) === 'array');
		assert.match(true, length(edit.changes[URI_A]) >= 1);
	});

	it('aliased import: renaming local alias stays within the importing file', () => {
		setupFiles(TEXT_A.text, TEXT_B_ALIASED.text);

		// on the call 'bar();' (local alias, not remote name)
		let edit = rename(URI_B, documents.get(URI_B), TEXT_B_ALIASED.at[0], 'baz');

		// should NOT produce edits in URI_A
		assert.match(true, edit.changes[URI_A] === null);
	});

	it('aliased import: renaming export changes only the remote name in import specifier', () => {
		setupFiles(TEXT_A.text, TEXT_B_ALIASED.text);

		// on the 'foo' export
		let edit = rename(URI_A, documents.get(URI_A), TEXT_A.at[0], 'baz');

		// URI_B gets exactly 1 edit: the 'foo' in '{ foo as bar }', not 'bar' uses
		assert.match([ { range: span(TEXT_B_ALIASED, 1, 2), newText: 'baz' } ], edit.changes[URI_B]);
	});

	it('aliased import in a mixed specifier list: renames only the remote name', () => {
		// `{ other, foo as bar }` — the leading non-aliased `other` used to make the
		// remote-name scan bail early and drop the `foo` rename edit entirely.
		let srcA = cursors("export function $0foo() { foo(); };\nexport function other() {};\n");
		let srcB = cursors("import { other, $1foo$2 as bar } from 'a';\nbar(); other();\n");
		setupFiles(srcA.text, srcB.text);

		let edit = rename(URI_A, documents.get(URI_A), srcA.at[0], 'baz');

		// just the remote `foo`
		assert.match([ { range: span(srcB, 1, 2), newText: 'baz' } ], edit.changes[URI_B]);
	});

	it('namespace import: renaming export updates property accesses in namespace importer', () => {
		setupFiles(TEXT_A.text, TEXT_B_NS.text);

		// on the 'foo' export
		let edit = rename(URI_A, documents.get(URI_A), TEXT_A.at[0], 'qux');

		// URI_B uses 'a.foo()' — should get an edit on the 'foo' property
		let editsB = edit.changes[URI_B];
		assert.match(true, type(editsB) === 'array');
		assert.match(true, length(editsB) >= 1);
		assert.match('qux', editsB[0].newText);
	});
});
