import { describe, it, assert, afterEach, beforeEach, prop, gen } from 'utest';
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

	it('resolves a forward reference to a later function declaration', () => {
		// ucode does NOT hoist function declarations (calling foo() above its
		// declaration is a runtime error), but there is only one `foo` in the
		// file, so go-to-definition should still jump to the declaration.
		let text = "foo();\nfunction foo() { return 1; }\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);       // the declaration below
		assert.match(9, result.range.start.character);  // 'foo' after 'function '
	});

	it('resolves a use of a let before its declaration in the same block', () => {
		let text = "x;\nlet x = 1;\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = definition(URI, doc, { line: 0, character: 0 });

		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);       // 'let x' below
		assert.match(4, result.range.start.character);
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
		// fixtures/template_lib.uc: {% export function render(name) {...}; %}
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

	it('does not module-jump on the string of a locally-shadowed require', () => {
		// a user `let require = …` is not the builtin loader
		let text = "let require = (n) => n;\nlet m = require(\"fixtures.greet\");\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let doc = documents.get(URI);

		// (1, 18) is inside the "fixtures.greet" argument
		let result = definition(URI, doc, { line: 1, character: 18 });
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

	it('jumps to a rest parameter of a function', () => {
		// function f(a, ...rest) — 'rest' is at col 17 (after 'function f(a, ...')
		let text = "function f(a, ...rest) {\n\treturn rest;\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 1, character: 8 });  // rest in `return rest`
		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(17, result.range.start.character);
	});

	it('jumps to a rest parameter of an arrow function', () => {
		// let g = (...xs) => xs; — 'xs' at col 12
		let text = "let g = (...xs) => xs;\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 0, character: 19 });  // xs in the body
		assert.match(0, result.range.start.line);
		assert.match(12, result.range.start.character);
	});
});

describe('definition — local (block/loop/catch) declarations', () => {
	it('jumps to a function-local let declaration', () => {
		let text = "function f() {\n\tlet x = 1;\n\treturn x;\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		// (2, 8) is 'x' in `return x`
		let result = definition(URI, doc, { line: 2, character: 8 });
		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);        // `let x` on line 1
		assert.match(5, result.range.start.character);   // 'x' after '\tlet '
	});

	it('resolves to the innermost let when a nested block shadows the name', () => {
		//  0: function f() {
		//  1: \tlet x = 1;
		//  2: \t{
		//  3: \t\tlet x = 2;      <- inner 'x' at col 6 (two tabs + 'let ')
		//  4: \t\treturn x;
		let text = "function f() {\n\tlet x = 1;\n\t{\n\t\tlet x = 2;\n\t\treturn x;\n\t}\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		// (4, 9) is 'x' in the inner block's `return x` (two tabs + 'return ')
		let result = definition(URI, doc, { line: 4, character: 9 });
		assert.match(URI, result.uri);
		assert.match(3, result.range.start.line);        // inner `let x` on line 3
		assert.match(6, result.range.start.character);
	});

	it('jumps to a for-in loop variable', () => {
		let text = "for (let k in obj) {\n\tprint(k);\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		// (1, 7) is 'k' in print(k)
		let result = definition(URI, doc, { line: 1, character: 7 });
		assert.match(URI, result.uri);
		assert.match(0, result.range.start.line);
		assert.match(9, result.range.start.character);   // 'k' after 'for (let '
	});

	it('jumps to a C-style for loop variable', () => {
		let text = "for (let i = 0; i < 3; i++) {\n\tprint(i);\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 1, character: 7 });
		assert.match(0, result.range.start.line);
		assert.match(9, result.range.start.character);   // 'i' after 'for (let '
	});

	it('jumps to a catch parameter', () => {
		let text = "try {} catch (e) {\n\tprint(e);\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 1, character: 7 });
		assert.match(0, result.range.start.line);
		assert.match(14, result.range.start.character);  // 'e' after 'try {} catch ('
	});

	it('jumps to the value variable of a two-variable for-in', () => {
		// for (let k, v in obj) — 'v' is bound at col 12 on line 0
		let text = "let obj = {};\nfor (let k, v in obj) {\n\tprint(v);\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 2, character: 7 });  // v in print(v)
		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);
		assert.match(12, result.range.start.character);  // 'v' after 'for (let k, '
	});

	it('a for-in without let assigns, so gd resolves to the real declaration', () => {
		// `for (x in …)` does not declare x; gd on the body x must reach `let x`.
		let text = "let x = 0;\nfor (x in [1]) {\n\tprint(x);\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 2, character: 7 });
		assert.match(0, result.range.start.line);         // the `let x`, not the loop header
		assert.match(4, result.range.start.character);
	});

	it('resolves an outer-function local captured by a nested closure', () => {
		//  1: \tlet cap = 1;      <- outer local, 'cap' at col 5
		//  3: \t\treturn cap;     <- captured inside inner(), 'cap' at col 9
		let text = "function outer() {\n\tlet cap = 1;\n\tfunction inner() {\n\t\treturn cap;\n\t}\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 3, character: 9 });
		assert.match(URI, result.uri);
		assert.match(1, result.range.start.line);         // outer's `let cap`
		assert.match(5, result.range.start.character);
	});

	it('resolves a parameter that shadows a builtin name to the parameter', () => {
		// 'length' is a builtin; as a param it must resolve locally, not to global.d.uc
		let text = "function f(length) {\n\treturn length;\n}\n";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		let result = definition(URI, doc, { line: 1, character: 8 });
		assert.match(URI, result.uri);                    // the param, not the builtin file
		assert.match(0, result.range.start.line);
		assert.match(11, result.range.start.character);   // 'length' after 'function f('
	});
});

// Property: for every local binder form, go-to-definition on a use site must
// resolve to a binding whose text is exactly the queried name. This fuzzes the
// whole binderIn/localScopeDef surface in one loop — the two-var and no-let
// for-in bugs would have been caught here by shrinking.
describe('definition — local binder identity (property)', () => {
	// Reference sites are placed on their own line so the use column is fixed
	// regardless of the (random) identifier length.
	function buildBinderSource(shape, n) {
		if (shape === "let")     return { src: sprintf("function f() {\n\tlet %s = 1;\n\t%s;\n}\n", n, n),                 use: { line: 2, character: 1 } };
		if (shape === "block")   return { src: sprintf("function f() {\n\t{\n\t\tlet %s = 1;\n\t\t%s;\n\t}\n}\n", n, n),   use: { line: 3, character: 2 } };
		if (shape === "for-in")  return { src: sprintf("for (let %s in [1]) {\n\t%s;\n}\n", n, n),                        use: { line: 1, character: 1 } };
		if (shape === "for-in2") return { src: sprintf("for (let k, %s in obj) {\n\t%s;\n}\n", n, n),                     use: { line: 1, character: 1 } };
		if (shape === "for-c")   return { src: sprintf("for (let %s = 0; %s < 3; %s++) {\n\t0;\n}\n", n, n, n),           use: { line: 0, character: 9 } };
		if (shape === "catch")   return { src: sprintf("try {} catch (%s) {\n\t%s;\n}\n", n, n),                          use: { line: 1, character: 1 } };
		if (shape === "param")   return { src: sprintf("function f(%s) {\n\t%s;\n}\n", n, n),                             use: { line: 1, character: 1 } };
		// arrow bare param
		return { src: sprintf("let g = %s => {\n\treturn %s;\n};\n", n, n),                                               use: { line: 1, character: 8 } };
	}

	// The identifier text at a resolved Location's start position.
	function identAt(src, pos) {
		let line = split(src, "\n")[pos.line];
		let m = match(substr(line, pos.character), /^[A-Za-z_][A-Za-z0-9_]*/);
		return m ? m[0] : "";
	}

	prop("gd on a local binder resolves to a node whose text is the name",
		gen.bind(gen.alphanumeric({ min_len: 1, max_len: 3 }), (raw) =>
			gen.map(gen.elements("let", "block", "for-in", "for-in2", "for-c", "catch", "param", "arrow"),
			        (shape) => ({ name: "v" + raw, shape }))),
		(c, ctx) => {
			ctx.classify(c.shape, true);
			let b = buildBinderSource(c.shape, c.name);
			dag.init(_config);
			documents.open(URI, b.src, 1);
			dag.add(URI, b.src, documents.get(URI).tree);
			let r = definition(URI, documents.get(URI), b.use);
			documents.close(URI);
			dag.remove(URI);
			assert.match(true, r !== null);
			assert.match(c.name, identAt(b.src, r.range.start));
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
