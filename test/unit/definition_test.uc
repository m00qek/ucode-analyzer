import { describe, it, assert, afterEach, beforeEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { definition } from 'ucode_language_server.definition';
import * as dag from 'ucode_language_server.dag';
import { invalidateUri } from 'ucode_language_server.memo';

let URI       = 'file:///test.uc';
let TS_URI    = 'file:///app/src/tree_sitter.uc';
let GREET_URI = 'file:///app/test/fixtures/greet.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src', 'test'] },
};

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(TS_URI);
	dag.remove(GREET_URI);
	invalidateUri(URI);
});

describe('definition — local declarations', () => {
	it('finds a let declaration by name', () => {
		let text = "let count = 0;\ncount;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// position (1, 0) is 'count' on the second line (the reference)
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);       // declaration is on line 0
		assert.match(4, result.range.start.character);  // 'count' starts at col 4
	});

	it('finds a const declaration', () => {
		let text = "const MAX = 100;\nMAX;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(6, result.range.start.character);  // 'MAX' starts at col 6
	});

	it('finds a function declaration', () => {
		let text = "function greet() {}\ngreet;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(9, result.range.start.character);  // 'greet' after 'function '
	});

	it('finds an exported let declaration', () => {
		let text = "export let x = 1;\nx;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
	});

	it('returns null for an unknown identifier', () => {
		let text = "foo;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null when cursor is on a non-identifier node', () => {
		let text = "let x = 5;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// position (0, 0) is 'l' in 'let' — anonymous token
		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null for position beyond end of file', () => {
		let text = "let x = 5;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		assert.match(null, definition(URI, doc, { line: 99, character: 0 }));
	});
});

describe('definition — named imports (inline export)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);
	});

	it('jumps to export function declaration in source file', () => {
		let text = "import { parse } from 'tree_sitter';\nparse;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 0) is the 'parse' reference on line 1
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(TS_URI, result.uri);
		// 'parse' is declared in tree_sitter.uc — just verify the uri and a line number
		assert.match(true, result.range.start.line >= 0);
	});

	it('returns null when the imported name does not exist in source', () => {
		let text = "import { doesNotExist } from 'tree_sitter';\ndoesNotExist;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(null, result);
	});
});

describe('definition — named imports (export clause)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(GREET_URI);
	});

	it('jumps to local function declaration for export { name } style', () => {
		// fixtures/greet.uc: function greet() {}  export { greet };
		let text = "import { greet } from 'fixtures.greet';\ngreet;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 0) is the 'greet' reference
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(GREET_URI, result.uri);
		assert.match(0, result.range.start.line);       // function greet() on line 0
		assert.match(9, result.range.start.character);  // 'greet' after 'function '
	});

	it('extractExports reports export-clause names in the DAG', () => {
		let exps = dag.exportsOf(GREET_URI);
		assert.match(true, exps !== null);
		assert.match(1, length(exps));
		assert.match('greet', exps[0].name);
		assert.match('function', exps[0].kind);
	});
});

describe('definition — function parameters', () => {
	it('jumps to parameter declaration in the enclosing function', () => {
		let text = "function parse(ts, opts) {\nts;\n}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// (1, 0) is 'ts' — a reference to the parameter
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);        // parameter declared on line 0
		assert.match(15, result.range.start.character);  // 'ts' at col 15 (after 'function parse(')
	});

	it('resolves to the innermost parameter when nested functions shadow the name', () => {
		// outer 'x' is at col 9; inner 'x' is at col 18 (after 'function inner(')
		let text = "function outer(x) {\nfunction inner(x) {\nx;\n}\n}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// (2, 0) is 'x' inside inner() — should resolve to inner's parameter
		let result = definition(URI, doc, { line: 2, character: 0 });

		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);        // inner's parameter is on line 1
		assert.match(15, result.range.start.character);  // 'x' after 'function inner('
	});

	it('does not match a parameter from a sibling function', () => {
		let text = "function a(x) {}\nfunction b() {\nx;\n}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// (2, 0) is 'x' inside b(), which has no parameter named x
		let result = definition(URI, doc, { line: 2, character: 0 });

		assert.match(null, result);
	});
});
