import { describe, it, assert, afterEach, beforeEach, mock } from 'utest';
import * as ts from 'tree_sitter';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { references } from 'ucode_analyzer.language_server.handlers.references';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

let _dagCfg = { workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src'] } };

let URI   = 'file:///test.uc';
let URI_A = 'file:///app/src/a.uc';
let URI_B = 'file:///app/src/b.uc';

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

	it('finds all occurrences of a rest parameter in the function body', () => {
		let text = "function f(...args) { return args[0]; }\n";
		documents.open(URI, text, 1);

		// cursor on 'args' in body (line 0, char 29)
		let locs = references(URI, documents.get(URI), { line: 0, character: 29 });

		// rest-element binding (declaration) + use in return = 2
		assert.match(2, length(locs));
	});

	it('finds loop variable references in C-style for condition and increment', () => {
		let text = "for (let i = 0; i < 10; i++) { i; }\n";
		documents.open(URI, text, 1);

		// cursor on 'i' in the condition (line 0, character 16)
		let locs = references(URI, documents.get(URI), { line: 0, character: 16 });

		// declaration + condition + increment + body = 4
		assert.match(4, length(locs));
	});

	it('excludes declaration site when includeDeclaration is false', () => {
		let text = "let x = 1;\nx;\nx;\n";
		documents.open(URI, text, 1);

		// cursor on declaration 'x' at (0, 4)
		let all  = references(URI, documents.get(URI), { line: 0, character: 4 }, true);
		let refs = references(URI, documents.get(URI), { line: 0, character: 4 }, false);

		// with declaration: 3 (decl + 2 uses); without: 2 (uses only)
		assert.match(3, length(all));
		assert.match(2, length(refs));
		// none of the ref-only locations should be on the declaration line
		for (let l in refs)
			assert.match(true, l.range.start.line > 0);
	});
});

describe('cross-file references', () => {
	let TEXT_A         = "export function foo() { foo(); };\n";
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

	it('named import: cursor in importing file returns locations in both files', () => {
		setupFiles(TEXT_A, TEXT_B_NAMED);

		// cursor on 'foo' in 'foo();' on line 1 of URI_B
		let locs = references(URI_B, documents.get(URI_B), { line: 1, character: 0 });

		let inA = filter(locs, (l) => l.uri === URI_A);
		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inA) >= 1);
		assert.match(true, length(inB) >= 1);
	});

	it('export declaration: cursor in declaring file returns locations in importing file', () => {
		setupFiles(TEXT_A, TEXT_B_NAMED);

		// cursor on 'foo' in 'export function foo()' in URI_A (line 0, char 16)
		let locs = references(URI_A, documents.get(URI_A), { line: 0, character: 16 });

		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inB) >= 1);
	});

	it('aliased import: cursor on local alias returns only within-file locations', () => {
		setupFiles(TEXT_A, TEXT_B_ALIASED);

		// cursor on 'bar' in 'bar();' on line 1 of URI_B — local alias, no cross-file
		let locs = references(URI_B, documents.get(URI_B), { line: 1, character: 0 });

		let inA = filter(locs, (l) => l.uri === URI_A);
		assert.match(0, length(inA));
		assert.match(true, length(locs) >= 1);
	});

	it('namespace import: cursor in declaring file returns property accesses in importer', () => {
		setupFiles(TEXT_A, TEXT_B_NS);

		// cursor on 'foo' export in URI_A (line 0, char 16)
		let locs = references(URI_A, documents.get(URI_A), { line: 0, character: 16 });

		// URI_B uses 'a.foo()' — the 'foo' property should appear as a cross-file location
		let inB = filter(locs, (l) => l.uri === URI_B);
		assert.match(true, length(inB) >= 1);
	});
});
