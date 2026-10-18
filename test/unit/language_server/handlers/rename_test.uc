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
		let src = cursors("let $0$1x$2 = 1;\n");
		let edit = renameAt(src, 'y');

		assert.match({ changes: { [URI]: [ { range: span(src, 1, 2), newText: 'y' } ] } }, edit);
	});

	it('produces one edit per occurrence', () => {
		let src = cursors("let $0$1x$2 = 1;\nlet y = $3x$4 + $5x$6;\n");
		let edit = renameAt(src, 'z');

		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]), ranges(edit.changes[URI]));
	});

	it('each edit has newText set to the new name', () => {
		let src = cursors("let $0$1x$2 = $3x$4;\n");
		let edit = renameAt(src, 'renamed');

		assert.match(any_order([
			{ range: span(src, 1, 2), newText: 'renamed' },
			{ range: span(src, 3, 4), newText: 'renamed' },
		]), edit.changes[URI]);
	});

	it('edit ranges span the exact identifier token', () => {
		let src = cursors("let $0$1count$2 = 0;\n");
		let edit = renameAt(src, 'total');

		assert.match([ { range: span(src, 1, 2), newText: 'total' } ], edit.changes[URI]);
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
	let TEXT_A         = cursors("export function $0$1foo$2() { $3foo$4(); };\n");
	let TEXT_B_NAMED   = cursors("import { $1foo$2 } from 'a';\n$0$3foo$4();\n");
	let TEXT_B_ALIASED = cursors("import { $1foo$2 as $3bar$4 } from 'a';\n$0$5bar$6();\n");
	let TEXT_B_NS      = cursors("import * as a from 'a';\na.$1foo$2();\n");

	// One edit per marker pair of `src`, all to `newText`.
	function edits(src, pairs, newText) {
		return any_order(map(pairs, (p) => ({ range: span(src, p[0], p[1]), newText })));
	}

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

		// declaring file: export declaration + internal call; importer: import binding + call
		assert.match({ changes: {
			[URI_A]: edits(TEXT_A, [ [ 1, 2 ], [ 3, 4 ] ], 'bar'),
			[URI_B]: edits(TEXT_B_NAMED, [ [ 1, 2 ], [ 3, 4 ] ], 'bar'),
		} }, edit);
	});

	it('named import: renaming from importer side updates both files', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the call 'foo();'
		let edit = rename(URI_B, documents.get(URI_B), TEXT_B_NAMED.at[0], 'baz');

		assert.match({ changes: {
			[URI_A]: edits(TEXT_A, [ [ 1, 2 ], [ 3, 4 ] ], 'baz'),
			[URI_B]: edits(TEXT_B_NAMED, [ [ 1, 2 ], [ 3, 4 ] ], 'baz'),
		} }, edit);
	});

	it('aliased import: renaming local alias stays within the importing file', () => {
		setupFiles(TEXT_A.text, TEXT_B_ALIASED.text);

		// on the call 'bar();' (local alias, not remote name)
		let edit = rename(URI_B, documents.get(URI_B), TEXT_B_ALIASED.at[0], 'baz');

		// the alias and its use only: no edits in URI_A, the remote `foo` untouched
		assert.match({ changes: {
			[URI_B]: edits(TEXT_B_ALIASED, [ [ 3, 4 ], [ 5, 6 ] ], 'baz'),
		} }, edit);
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
		assert.match({ changes: {
			[URI_A]: edits(TEXT_A, [ [ 1, 2 ], [ 3, 4 ] ], 'qux'),
			[URI_B]: [ { range: span(TEXT_B_NS, 1, 2), newText: 'qux' } ],
		} }, edit);
	});
});

describe('rename — export aliases and re-exports', () => {
	let URI_C = fixture.uri('c.uc');

	// Index and open files ({ uri: cursors() result }), their imports
	// resolving to each other.
	function setup(files) {
		let data = {};
		for (let uri, src in files) data[fixture.WORKSPACE + '/' + replace(uri, /^.*\//, '')] = src.text;
		mock.global.patch('fs', { data });
		for (let uri, src in files) dag.add(uri, src.text, parse(src.text));
		mock.global.unpatch('fs');
		for (let uri, src in files) documents.open(uri, src.text, 1);
	}

	function edits(src, pairs, newText) {
		return any_order(map(pairs, (p) => ({ range: span(src, p[0], p[1]), newText })));
	}

	beforeEach(() => dag.init(fixture.config()));

	afterEach(() => {
		for (let uri in [ URI_A, URI_B, URI_C ]) {
			documents.close(uri);
			dag.remove(uri);
		}
	});

	it('renames through `export { foo }` of an import to that module\'s importers', () => {
		let a = cursors("export function $0$1foo$2() {};\n");
		let b = cursors("import { $1foo$2 } from 'a';\nexport { $3foo$4 };\n");
		let c = cursors("import { $1foo$2 } from 'b';\n$3foo$4();\n");
		setup({ [URI_A]: a, [URI_B]: b, [URI_C]: c });

		assert.match({ changes: {
			[URI_A]: edits(a, [ [ 1, 2 ] ], 'bar'),
			[URI_B]: edits(b, [ [ 1, 2 ], [ 3, 4 ] ], 'bar'),
			[URI_C]: edits(c, [ [ 1, 2 ], [ 3, 4 ] ], 'bar'),
		} }, rename(URI_A, documents.get(URI_A), a.at[0], 'bar'));
	});

	it('renames, from an export alias, the alias and its importers', () => {
		let a = cursors("let x = 1;\nexport { x as $0$1foo$2 };\n");
		let b = cursors("import { $1foo$2 } from 'a';\n$3foo$4;\n");
		setup({ [URI_A]: a, [URI_B]: b });

		assert.match({ changes: {
			[URI_A]: edits(a, [ [ 1, 2 ] ], 'bar'),
			[URI_B]: edits(b, [ [ 1, 2 ], [ 3, 4 ] ], 'bar'),
		} }, rename(URI_A, documents.get(URI_A), a.at[0], 'bar'));
	});

	it('renames the local of an export alias in its file only', () => {
		let a = cursors("let $0$1x$2 = 1;\nexport { $3x$4 as foo };\n");
		let b = cursors("import { foo } from 'a';\nfoo;\n");
		setup({ [URI_A]: a, [URI_B]: b });

		assert.match({ changes: { [URI_A]: edits(a, [ [ 1, 2 ], [ 3, 4 ] ], 'y') } },
			rename(URI_A, documents.get(URI_A), a.at[0], 'y'));
	});
});
