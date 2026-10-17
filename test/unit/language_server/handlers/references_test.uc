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
		let locs = refsAt(cursors("let $0x = 1;\nlet y = x + x;\n"));

		// x appears 3 times: declaration + two uses
		assert.match(3, length(locs));
	});

	it('each location has the correct uri', () => {
		let locs = refsAt(cursors("let $0z = 0;\nz;\n"));

		assert.match(2, length(locs));
		for (let l in locs)
			assert.match(URI, l.uri);
	});

	it('locations are on the correct lines', () => {
		let src = cursors("let $0$1v$2 = 1;\n$3v$4;\n$5v$6;\n");
		let locs = refsAt(src);

		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]), ranges(locs));
	});

	it('finds single occurrence when identifier appears only once', () => {
		let locs = refsAt(cursors("$0unique;\n"));

		assert.match(1, length(locs));
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

	it('does not mix outer and inner let bindings with the same name', () => {
		// Outer x and inner x (shadowed) are separate bindings.
		let src = cursors("let $0x = 1;\nfunction foo() {\n  let $1x = 2;\n  return x;\n}\nx;\n");
		documents.open(URI, src.text, 1);

		let outer = references(URI, documents.get(URI), src.at[0]);
		let inner = references(URI, documents.get(URI), src.at[1]);

		// Outer x: declaration + the use after foo = 2
		assert.match(2, length(outer));
		// Inner x: declaration + return = 2
		assert.match(2, length(inner));
	});

	it('finds all occurrences of a for-in loop variable within its body', () => {
		// on a use in the loop body
		let locs = refsAt(cursors("let arr = [];\nfor (let i in arr) {\n  $0i;\n  i;\n}\n"));

		// declaration (for-in variable) + 2 uses = 3
		assert.match(3, length(locs));
	});

	it('finds both the declaration and use of a catch variable', () => {
		// on the use inside the catch body
		let locs = refsAt(cursors("try {\n} catch(e) {\n  $0e;\n}\n"));

		// catch parameter declaration + use = 2
		assert.match(2, length(locs));
	});

	it('finds all occurrences of a rest parameter in the function body', () => {
		// on the use in the body
		let locs = refsAt(cursors("function f(...args) { return $0args[0]; }\n"));

		// rest-element binding (declaration) + use in return = 2
		assert.match(2, length(locs));
	});

	it('finds loop variable references in C-style for condition and increment', () => {
		// on the use in the condition
		let locs = refsAt(cursors("for (let i = 0; $0i < 10; i++) { i; }\n"));

		// declaration + condition + increment + body = 4
		assert.match(4, length(locs));
	});

	it('excludes declaration site when includeDeclaration is false', () => {
		let src = cursors("let $0x = 1;\n$1x$2;\n$3x$4;\n");
		documents.open(URI, src.text, 1);

		let all  = references(URI, documents.get(URI), src.at[0], true);
		let refs = references(URI, documents.get(URI), src.at[0], false);

		// with declaration: 3 (decl + 2 uses); without: the 2 uses only
		assert.match(3, length(all));
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]), ranges(refs));
	});
});

describe('cross-file references', () => {
	let TEXT_A         = cursors("export function $0foo() { foo(); };\n");
	let TEXT_B_NAMED   = cursors("import { foo } from 'a';\n$0foo();\n");
	let TEXT_B_ALIASED = cursors("import { foo as bar } from 'a';\n$0bar();\n");
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

	it('named import: cursor in importing file returns locations in both files', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the call 'foo();'
		let locs = references(URI_B, documents.get(URI_B), TEXT_B_NAMED.at[0]);

		let inA = filter(locs, (l) => l.uri === URI_A);
		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inA) >= 1);
		assert.match(true, length(inB) >= 1);
	});

	it('export declaration: cursor in declaring file returns locations in importing file', () => {
		setupFiles(TEXT_A.text, TEXT_B_NAMED.text);

		// on the declared name in 'export function foo()'
		let locs = references(URI_A, documents.get(URI_A), TEXT_A.at[0]);

		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inB) >= 1);
	});

	it('aliased import: cursor on local alias returns only within-file locations', () => {
		setupFiles(TEXT_A.text, TEXT_B_ALIASED.text);

		// on the call 'bar();' — a local alias, no cross-file
		let locs = references(URI_B, documents.get(URI_B), TEXT_B_ALIASED.at[0]);

		let inA = filter(locs, (l) => l.uri === URI_A);
		assert.match(0, length(inA));
		assert.match(true, length(locs) >= 1);
	});

	it('namespace import: cursor in declaring file returns property accesses in importer', () => {
		setupFiles(TEXT_A.text, TEXT_B_NS.text);

		// on the 'foo' export
		let locs = references(URI_A, documents.get(URI_A), TEXT_A.at[0]);

		// URI_B uses 'a.foo()' — the 'foo' property should appear as a cross-file location
		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inB) >= 1);
	});
});
