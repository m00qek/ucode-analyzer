import { describe, it, assert, afterEach, beforeEach, mock, any_order } from 'utest';
import * as ts from 'tree_sitter';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { references } from 'ucode_analyzer.language_server.handlers.references';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

let URI   = 'file:///test.uc';
let URI_A = fixture.uri('a.uc');
let URI_B = fixture.uri('b.uc');

// Open the text of `src` (from cursors()) and find the references at $0.
function refsAt(src, includeDeclaration) {
	documents.open(URI, src.text, 1);
	return references(URI, documents.get(URI), src.at[0], includeDeclaration);
}

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

function ranges(locs) {
	return map(locs, (l) => l.range);
}

afterEach(() => documents.close(URI));

describe('references', () => {
	it('returns null when cursor is not on an identifier', () => {
		// 'let' is an anonymous token
		assert.match(null, refsAt(cursors("$0let x = 1;\n")));
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);

		assert.match(null, references(URI, documents.get(URI), { line: 99, character: 0 }));
	});

	it('finds all occurrences of an identifier', () => {
		// on the declaration
		let src = cursors("let $0$1x$2 = 1;\nlet y = $3x$4 + $5x$6;\n");

		// declaration + two uses
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]), ranges(refsAt(src)));
	});

	it('each location has the correct uri', () => {
		let src = cursors("let $0$1z$2 = 0;\n$3z$4;\n");

		assert.match(any_order([
			{ uri: URI, range: span(src, 1, 2) },
			{ uri: URI, range: span(src, 3, 4) },
		]), refsAt(src));
	});

	it('locations are on the correct lines', () => {
		let src = cursors("let $0$1v$2 = 1;\n$3v$4;\n$5v$6;\n");
		let locs = refsAt(src);

		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]), ranges(locs));
	});

	it('finds single occurrence when identifier appears only once', () => {
		let src = cursors("$0$1unique$2;\n");

		assert.match([ { uri: URI, range: span(src, 1, 2) } ], refsAt(src));
	});
});

describe('references — binding forms', () => {
	// Each: the references of the outer name at $0 are $1–$2 and $3–$4 (and $5–$6).
	function outer(marked) {
		let src = cursors(marked);
		let want = [ span(src, 1, 2), span(src, 3, 4) ];
		if (src.at[5]) push(want, span(src, 5, 6));
		return [ any_order(want), ranges(refsAt(src)) ];
	}

	it('a catch parameter is its own name', () => {
		let r = outer("let $0$1e$2 = 1;\ntry { f(); } catch (e) { e; }\n$3e$4;\n");
		assert.match(r[0], r[1]);
	});

	it('an export alias is not a use', () => {
		let r = outer("let $0$1b$2 = 1;\nlet a = 2;\nexport { a as b };\n$3b$4;\n");
		assert.match(r[0], r[1]);
	});

	it('the loop variable of an alt-syntax for-in is its own name', () => {
		let r = outer("{% let $0$1x$2 = [1]; for (let x in $3x$4): %}{{ x }}{% endfor %}\n");
		assert.match(r[0], r[1]);
	});

	it('a for initializer sees the declarators before it', () => {
		let r = outer("let $0$1i$2 = 9;\nfor (let i = 0, j = i; i < 1; i++) j;\n$3i$4;\n");
		assert.match(r[0], r[1]);
	});

	it('a named function expression sees its own name', () => {
		let r = outer("let $0$1g$2 = 1;\nlet f = function g() { return g; };\n$3g$4;\n");
		assert.match(r[0], r[1]);
	});

	it('`for (x in …)` without let assigns the outer x', () => {
		let r = outer("let $0$1x$2;\nfor ($3x$4 in [1]) $5x$6;\n");
		assert.match(r[0], r[1]);
	});
});

describe('references — scope awareness', () => {
	it('does not cross function-scope boundaries for parameters with the same name', () => {
		// Two functions both have a parameter called `x`.
		// References on function a's x must not include function b's x.
		let src = cursors("function a($0$1x$2) { return $3x$4; }\nfunction b(x) { return x; }\n");
		let locs = refsAt(src);

		// Only the declaration and use inside `a` — 2 total, not 4.
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(locs));
	});

	it('keeps the bare parameter of an arrow function apart from an outer name', () => {
		let src = cursors("let $0$1x$2 = 1;\nlet f = x => x + 1;\n$3x$4;\n");
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(refsAt(src)));
	});

	it('does not mix outer and inner let bindings with the same name', () => {
		// Outer x and inner x (shadowed) are separate bindings.
		let src = cursors("let $0$1x$2 = 1;\nfunction foo() {\n  let $3$4x$5 = 2;\n  return $6x$7;\n}\n$8x$9;\n");
		documents.open(URI, src.text, 1);

		let outer = references(URI, documents.get(URI), src.at[0]);
		let inner = references(URI, documents.get(URI), src.at[3]);

		// Outer x: declaration + the use after foo
		assert.match(any_order([ span(src, 1, 2), span(src, 8, 9) ]), ranges(outer));
		// Inner x: declaration + return
		assert.match(any_order([ span(src, 4, 5), span(src, 6, 7) ]), ranges(inner));
	});

	it('finds all occurrences of a for-in loop variable within its body', () => {
		// on a use in the loop body
		let src = cursors("let arr = [];\nfor (let $1i$2 in arr) {\n  $0$3i$4;\n  $5i$6;\n}\n");

		// declaration (for-in variable) + 2 uses
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]), ranges(refsAt(src)));
	});

	it('finds both the declaration and use of a catch variable', () => {
		// on the use inside the catch body
		let src = cursors("try {\n} catch($1e$2) {\n  $0$3e$4;\n}\n");

		// catch parameter declaration + use
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(refsAt(src)));
	});

	it('finds all occurrences of a rest parameter in the function body', () => {
		// on the use in the body
		let src = cursors("function f(...$1args$2) { return $0$3args$4[0]; }\n");

		// rest-element binding (declaration) + use in return
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(refsAt(src)));
	});

	it('finds loop variable references in C-style for condition and increment', () => {
		// on the use in the condition
		let src = cursors("for (let $1i$2 = 0; $0$3i$4 < 10; $5i$6++) { $7i$8; }\n");

		// declaration + condition + increment + body
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6), span(src, 7, 8) ]), ranges(refsAt(src)));
	});

	it('excludes declaration site when includeDeclaration is false', () => {
		let src = cursors("let $0$5x$6 = 1;\n$1x$2;\n$3x$4;\n");
		documents.open(URI, src.text, 1);

		let all  = references(URI, documents.get(URI), src.at[0], true);
		let refs = references(URI, documents.get(URI), src.at[0], false);

		// with declaration: decl + 2 uses; without: the 2 uses only
		assert.match(any_order([ span(src, 5, 6), span(src, 1, 2), span(src, 3, 4) ]), ranges(all));
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(refs));
	});
});

describe('cross-file references', () => {
	let TEXT_A         = cursors("export function $0$1foo$2() { $3foo$4(); };\n");
	let TEXT_B_NAMED   = cursors("import { $1foo$2 } from 'a';\n$0$3foo$4();\n");
	let TEXT_B_ALIASED = cursors("import { foo as $1bar$2 } from 'a';\n$0$3bar$4();\n");
	let TEXT_B_NS      = cursors("import * as a from 'a';\na.$1foo$2();\n");

	// The location of marker pair a–b of `src` in `uri`.
	function loc(uri, src, a, b) {
		return { uri, range: span(src, a, b) };
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

	it('named import: cursor in importing file returns locations in both files', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the call 'foo();'
		let locs = references(URI_B, documents.get(URI_B), TEXT_B_NAMED.at[0]);

		assert.match(any_order([
			loc(URI_A, TEXT_A, 1, 2), loc(URI_A, TEXT_A, 3, 4),
			loc(URI_B, TEXT_B_NAMED, 1, 2), loc(URI_B, TEXT_B_NAMED, 3, 4),
		]), locs);
	});

	it('export declaration: cursor in declaring file returns locations in importing file', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the declared name in 'export function foo()'
		let locs = references(URI_A, documents.get(URI_A), TEXT_A.at[0]);

		assert.match(any_order([
			loc(URI_A, TEXT_A, 1, 2), loc(URI_A, TEXT_A, 3, 4),
			loc(URI_B, TEXT_B_NAMED, 1, 2), loc(URI_B, TEXT_B_NAMED, 3, 4),
		]), locs);
	});

	it('aliased import: cursor on local alias returns its locations and the export\'s', () => {
		setupFiles(TEXT_A.text, TEXT_B_ALIASED.text);

		// on the call 'bar();'
		let locs = references(URI_B, documents.get(URI_B), TEXT_B_ALIASED.at[0]);

		assert.match(any_order([
			loc(URI_A, TEXT_A, 1, 2), loc(URI_A, TEXT_A, 3, 4),
			loc(URI_B, TEXT_B_ALIASED, 1, 2), loc(URI_B, TEXT_B_ALIASED, 3, 4),
		]), locs);
	});

	it('export alias: cursor on it returns the local\'s locations and the importer\'s', () => {
		let srcA = cursors("let $1x$2 = 1;\nexport { $3x$4 as $0foo };\n");
		setupFiles(srcA.text, TEXT_B_NAMED.text);

		let locs = references(URI_A, documents.get(URI_A), srcA.at[0]);

		assert.match(any_order([
			loc(URI_A, srcA, 1, 2), loc(URI_A, srcA, 3, 4),
			loc(URI_B, TEXT_B_NAMED, 1, 2), loc(URI_B, TEXT_B_NAMED, 3, 4),
		]), locs);
	});

	it('import of a name the module lacks: only within-file locations', () => {
		let srcB = cursors("import { $1nope$2 } from 'a';\n$0$3nope$4();\n");
		setupFiles(TEXT_A.text, srcB.text);

		let locs = references(URI_B, documents.get(URI_B), srcB.at[0]);

		assert.match(any_order([ loc(URI_B, srcB, 1, 2), loc(URI_B, srcB, 3, 4) ]), locs);
	});

	it('namespace import: cursor in declaring file returns property accesses in importer', () => {
		setupFiles(TEXT_A.text, TEXT_B_NS.text);

		// on the 'foo' export
		let locs = references(URI_A, documents.get(URI_A), TEXT_A.at[0]);

		// URI_B uses 'a.foo()' — the 'foo' property should appear as a cross-file location
		assert.match(any_order([
			loc(URI_A, TEXT_A, 1, 2), loc(URI_A, TEXT_A, 3, 4), loc(URI_B, TEXT_B_NS, 1, 2),
		]), locs);
	});
});

describe('references — through a re-export', () => {
	let URI_C = fixture.uri('c.uc');
	let A = cursors("export function $1foo$2() {};\n");
	let B = cursors("import { $1foo$2 } from 'a';\nexport { $3foo$4 };\n");
	let C = cursors("import { $1foo$2 } from 'b';\n$0$3foo$4();\n");

	beforeEach(() => {
		dag.init(fixture.config());
		let files = { [URI_A]: A, [URI_B]: B, [URI_C]: C };
		let data = {};
		for (let uri, src in files) data[fixture.WORKSPACE + '/' + replace(uri, /^.*\//, '')] = src.text;
		mock.global.patch('fs', { data });
		for (let uri, src in files) dag.add(uri, src.text, parse(src.text));
		mock.global.unpatch('fs');
		for (let uri, src in files) documents.open(uri, src.text, 1);
	});

	afterEach(() => {
		for (let uri in [ URI_A, URI_B, URI_C ]) {
			documents.close(uri);
			dag.remove(uri);
		}
	});

	it('finds, from an importer of the re-export, the declaring module and the re-exporting one', () => {
		assert.match(any_order([
			{ uri: URI_A, range: span(A, 1, 2) },
			{ uri: URI_B, range: span(B, 1, 2) }, { uri: URI_B, range: span(B, 3, 4) },
			{ uri: URI_C, range: span(C, 1, 2) }, { uri: URI_C, range: span(C, 3, 4) },
		]), references(URI_C, documents.get(URI_C), C.at[0]));
	});

	it('drops the declaration in the declaring module without includeDeclaration', () => {
		let locs = references(URI_C, documents.get(URI_C), C.at[0], false);
		assert.match([], filter(locs, (l) => l.uri === URI_A));
	});
});
