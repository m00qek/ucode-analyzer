import { describe, it, assert, afterEach, beforeEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { definition } from 'language_server.handlers.definition';
import * as dag from 'code_analysis.dag.dag';
import { invalidateUri } from 'code_analysis.memo';

let URI       = 'file:///test.uc';
let TS_URI    = 'file:///app/src/tree_sitter.uc';
let GREET_URI = 'file:///app/test/fixtures/greet.uc';
let TPL_URI   = 'file:///app/test/fixtures/template_lib.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src', 'test'] },
};

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(TS_URI);
	dag.remove(GREET_URI);
	dag.remove(TPL_URI);
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

describe('definition — cross-file into a template module', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TPL_URI);
	});

	it('jumps to an export declared inside a {% %} tag in a template file', () => {
		// fixtures/template_lib.uc: {% export function render(name) {...} %}
		let text = "import { render } from 'fixtures.template_lib';\nrender;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 0) is the 'render' reference
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(TPL_URI, result.uri);
		assert.match(0, result.range.start.line);        // export is on line 0 of the template
		assert.match(19, result.range.start.character);  // 'render' after '{% export function '
	});
});

describe('definition — namespace import alias', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);
	});

	it('jumps to the top of the imported module file', () => {
		let text = "import * as ts from 'tree_sitter';\nts;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 0) is 'ts' — the namespace alias reference
		let result = definition(URI, doc, { line: 1, character: 0 });

		assert.match(TS_URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(0, result.range.start.character);
	});

	it('returns null for an identifier that is not a namespace alias', () => {
		let text = "import * as ts from 'tree_sitter';\nnotAlias;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 0 });
		assert.match(null, result);
	});
});

describe('definition — member expression (namespace import)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);
	});

	it('jumps to the export in the module when cursor is on the property', () => {
		// 'parse' is an export of tree_sitter.uc; cursor on 'parse' in ts.parse()
		// Column: "import * as ts from 'tree_sitter';\nts.parse;\n" — 'parse' starts at col 3
		let text = "import * as ts from 'tree_sitter';\nts.parse;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 3 });

		assert.match(TS_URI, result.uri);
		assert.match(true, result.range.start.line >= 0);
	});

	it('returns null for a property not exported by the module', () => {
		let text = "import * as ts from 'tree_sitter';\nts.doesNotExist;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 1, character: 3 });
		assert.match(null, result);
	});
});

describe('definition — require() module loader', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(GREET_URI);
	});

	// fixtures/greet.uc: function greet() {}  export { greet };
	it('jumps to the module file when cursor is on the require() string', () => {
		let text = "let mod = require(\"fixtures.greet\");\nmod.greet;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (0, 20) is inside the "fixtures.greet" specifier
		let result = definition(URI, doc, { line: 0, character: 20 });
		assert.match(GREET_URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(0, result.range.start.character);
	});

	it('jumps to the module file from a use of the require-bound variable', () => {
		let text = "let mod = require(\"fixtures.greet\");\nmod.greet;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 0) is 'mod' — the module-typed variable reference
		let result = definition(URI, doc, { line: 1, character: 0 });
		assert.match(GREET_URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(0, result.range.start.character);
	});

	it('jumps into the module on member access of a require-bound variable', () => {
		let text = "let mod = require(\"fixtures.greet\");\nmod.greet;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 4) is 'greet' in mod.greet
		let result = definition(URI, doc, { line: 1, character: 4 });
		assert.match(GREET_URI, result.uri);
	});

	it('does not treat a non-require string literal as a module jump', () => {
		let text = "let s = \"fixtures.greet\";\ns;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 0, character: 12 });
		assert.match(null, result);
	});

	// fixtures/legacy_mod.uc exports via a top-level `return { greet, version }`.
	it('jumps into a legacy (return-object) module on member access', () => {
		let LEGACY_URI = 'file:///app/test/fixtures/legacy_mod.uc';
		dag.addFromDisk(LEGACY_URI);
		let text = "let m = require(\"fixtures.legacy_mod\");\nm.greet;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 2) is 'greet' in m.greet
		let result = definition(URI, doc, { line: 1, character: 2 });
		assert.match(LEGACY_URI, result.uri);
		dag.remove(LEGACY_URI);
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

describe('definition — member expression (record type, named import)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);
	});

	afterEach(() => dag.remove(TS_URI));

	it('jumps to record field key when cursor is on property of named import', () => {
		// tree_sitter exports { newParser, parse, ... } as top-level functions,
		// but also queryMatches etc.  Use a local record to keep the test
		// self-contained and independent of tree_sitter.uc layout.
		let text = "let api = { greet: function(name) {}, bye: function() {} };\napi.greet;";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on 'greet' in 'api.greet' — line 1, character 4
		let result = definition(URI, documents.get(URI), { line: 1, character: 4 });

		assert.match(true, result !== null);
		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(12, result.range.start.character);  // 'greet' after '{ '
	});

	it('returns null when property does not exist on the record', () => {
		let text = "let api = { greet: function() {} };\napi.doesNotExist;";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = definition(URI, documents.get(URI), { line: 1, character: 4 });

		assert.match(null, result);
	});
});

describe('definition — chained member expression', () => {
	beforeEach(() => dag.init(_config));

	it('jumps to a field on a nested record (a.b.c where a.b is a record)', () => {
		// 'api.sub.go' — api.sub is a record with field 'go'
		let text = "let api = { sub: { go: function() {}, stop: function() {} } };\napi.sub.go;";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on 'go' in 'api.sub.go' — line 1, character 8
		let result = definition(URI, documents.get(URI), { line: 1, character: 8 });

		assert.match(true, result !== null);
		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(19, result.range.start.character);  // 'go' after '{ sub: { '
	});

	it('returns null when intermediate member does not exist', () => {
		let text = "let api = { sub: { go: function() {} } };\napi.missing.go;";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = definition(URI, documents.get(URI), { line: 1, character: 12 });

		assert.match(null, result);
	});
});
