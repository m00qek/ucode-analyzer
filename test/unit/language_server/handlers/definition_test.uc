import { describe, it, assert, afterEach, beforeEach, prop, gen } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { definition } from 'ucode_analyzer.language_server.handlers.definition';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { cursors, locate } from 'cursor';
import * as fixture from 'fixture';

let URI        = 'file:///test.uc';
let PARSER_URI = fixture.uri('parser.uc');
let GREET_URI  = fixture.uri('greet.uc');
let TPL_URI    = fixture.uri('template_lib.uc');
let DE_URI     = fixture.uri('default_export.uc');

let _config = fixture.config();

// Open the text and go to the definition at its $0.
function definitionAt(src) {
	documents.open(URI, src.text, 1);
	return definition(URI, documents.get(URI), src.at[0]);
}

// The same, with the text in the DAG so its imports resolve.
function definitionImporting(src) {
	documents.open(URI, src.text, 1);
	dag.add(URI, src.text, documents.get(URI).tree);
	return definition(URI, documents.get(URI), src.at[0]);
}

// The zero-width Location definition() returns for `pos` in `uri`.
function point(uri, pos) {
	return { uri, range: { start: pos, end: pos } };
}

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(PARSER_URI);
	dag.remove(GREET_URI);
	dag.remove(TPL_URI);
	dag.remove(DE_URI);
	invalidateUri(URI);
});

describe('definition — local declarations', () => {
	it('finds a let declaration by name', () => {
		let src = cursors("let $1count = 0;\n$0count;");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('finds a const declaration', () => {
		let src = cursors("const $1MAX = 100;\n$0MAX;");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('finds a function declaration', () => {
		let src = cursors("function $1greet() {}\n$0greet;");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('resolves a forward reference to a later function declaration', () => {
		// ucode does NOT hoist function declarations (calling foo() above its
		// declaration is a runtime error), but there is only one `foo` in the
		// file, so go-to-definition should still jump to the declaration.
		let src = cursors("$0foo();\nfunction $1foo() { return 1; }\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('resolves a use of a let before its declaration in the same block', () => {
		let src = cursors("$0x;\nlet $1x = 1;\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('finds an exported let declaration', () => {
		let src = cursors("export let $1x = 1;\n$0x;");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('returns null for an unknown identifier', () => {
		assert.match(null, definitionAt(cursors("$0foo;")));
	});

	it('returns null when cursor is on a non-identifier node', () => {
		// 'let' is an anonymous token
		assert.match(null, definitionAt(cursors("$0let x = 5;")));
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
		dag.addFromDisk(PARSER_URI);
	});

	it('jumps to export function declaration in source file', () => {
		let result = definitionImporting(cursors("import { parse } from 'parser';\n$0parse;\n"));

		assert.match(point(PARSER_URI, locate(fixture.read('parser.uc'), 'export function parse(', 0, length('export function '))), result);
	});

	it('returns null when the imported name does not exist in source', () => {
		let result = definitionImporting(cursors("import { doesNotExist } from 'parser';\n$0doesNotExist;\n"));

		assert.match(null, result);
	});
});

describe('definition — named imports (export clause)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(GREET_URI);
	});

	it('jumps to local function declaration for export { name } style', () => {
		// greet.uc: function greet() {}  export { greet };
		let result = definitionImporting(cursors("import { greet } from 'greet';\n$0greet;\n"));

		assert.match(point(GREET_URI, locate(fixture.read('greet.uc'), 'function greet', 0, length('function '))), result);
	});

	it('extractExports reports export-clause names in the DAG', () => {
		assert.match([ {
			name: 'greet', kind: 'function', doc: null, params: [], valueType: null,
			position: locate(fixture.read('greet.uc'), 'function greet', 0, length('function ')),
			local: 'greet',
		} ], dag.exportsOf(GREET_URI));
	});
});

describe('definition — cross-file default import', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(DE_URI);
	});

	it('jumps from a default-imported name to the `export default` value', () => {
		// default_export.uc: export default { k: 2 };
		let result = definitionImporting(cursors("import x from 'default_export';\n$0x;\n"));

		assert.match(point(DE_URI, locate(fixture.read('default_export.uc'), 'export default {', 0, length('export default '))), result);
	});
});

describe('definition — cross-file into a template module', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TPL_URI);
	});

	it('jumps to an export declared inside a {% %} tag in a template file', () => {
		// template_lib.uc: {% export function render(name) {...}; %}
		let result = definitionImporting(cursors("import { render } from 'template_lib';\n$0render;\n"));

		assert.match(point(TPL_URI, locate(fixture.read('template_lib.uc'), 'export function render', 0, length('export function '))), result);
	});
});

describe('definition — namespace import alias', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(PARSER_URI);
	});

	it('jumps to the top of the imported module file', () => {
		let result = definitionImporting(cursors("import * as p from 'parser';\n$0p;\n"));

		assert.match(point(PARSER_URI, { line: 0, character: 0 }), result);
	});

	it('returns null for an identifier that is not a namespace alias', () => {
		let result = definitionImporting(cursors("import * as p from 'parser';\n$0notAlias;\n"));
		assert.match(null, result);
	});
});

describe('definition — member expression (namespace import)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(PARSER_URI);
	});

	it('jumps to the export in the module when cursor is on the property', () => {
		let result = definitionImporting(cursors("import * as p from 'parser';\np.$0parse;\n"));

		assert.match(point(PARSER_URI, locate(fixture.read('parser.uc'), 'export function parse(', 0, length('export function '))), result);
	});

	it('returns null for a property not exported by the module', () => {
		let result = definitionImporting(cursors("import * as p from 'parser';\np.$0doesNotExist;\n"));
		assert.match(null, result);
	});
});

describe('definition — require() module loader', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(GREET_URI);
	});

	// greet.uc: function greet() {}  export { greet };
	it('jumps to the module file when cursor is on the require() string', () => {
		let result = definitionImporting(cursors("let mod = require(\"gr$0eet\");\nmod.greet;\n"));
		assert.match(point(GREET_URI, { line: 0, character: 0 }), result);
	});

	it('jumps to the module file from a use of the require-bound variable', () => {
		let result = definitionImporting(cursors("let mod = require(\"greet\");\n$0mod.greet;\n"));
		assert.match(point(GREET_URI, { line: 0, character: 0 }), result);
	});

	it('jumps into the module on member access of a require-bound variable', () => {
		let result = definitionImporting(cursors("let mod = require(\"greet\");\nmod.$0greet;\n"));
		assert.match(point(GREET_URI, locate(fixture.read('greet.uc'), 'function greet', 0, length('function '))), result);
	});

	it('does not treat a non-require string literal as a module jump', () => {
		let result = definitionImporting(cursors("let s = \"gre$0et\";\ns;\n"));
		assert.match(null, result);
	});

	it('does not module-jump on the string of a locally-shadowed require', () => {
		// a user `let require = …` is not the builtin loader
		let result = definitionImporting(cursors("let require = (n) => n;\nlet m = require(\"gr$0eet\");\n"));
		assert.match(null, result);
	});

	// legacy_mod.uc exports via a top-level `return { greet, version }`.
	it('jumps into a legacy (return-object) module on member access', () => {
		let LEGACY_URI = fixture.uri('legacy_mod.uc');
		dag.addFromDisk(LEGACY_URI);
		let result = definitionImporting(cursors("let m = require(\"legacy_mod\");\nm.$0greet;\n"));
		assert.match(point(LEGACY_URI, locate(fixture.read('legacy_mod.uc'), 'greet: function')), result);
		dag.remove(LEGACY_URI);
	});
});

describe('definition — function parameters', () => {
	it('jumps to parameter declaration in the enclosing function', () => {
		let src = cursors("function parse($1ts, opts) {\n$0ts;\n}");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('resolves to the innermost parameter when nested functions shadow the name', () => {
		let src = cursors("function outer(x) {\nfunction inner($1x) {\n$0x;\n}\n}");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('does not match a parameter from a sibling function', () => {
		// x inside b(), which has no parameter named x
		assert.match(null, definitionAt(cursors("function a(x) {}\nfunction b() {\n$0x;\n}")));
	});

	it('jumps to a rest parameter of a function', () => {
		let src = cursors("function f(a, ...$1rest) {\n\treturn $0rest;\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a rest parameter of an arrow function', () => {
		let src = cursors("let g = (...$1xs) => $0xs;\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});
});

describe('definition — local (block/loop/catch) declarations', () => {
	it('jumps to a function-local let declaration', () => {
		let src = cursors("function f() {\n\tlet $1x = 1;\n\treturn $0x;\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('resolves to the innermost let when a nested block shadows the name', () => {
		let src = cursors("function f() {\n\tlet x = 1;\n\t{\n\t\tlet $1x = 2;\n\t\treturn $0x;\n\t}\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a for-in loop variable', () => {
		let src = cursors("for (let $1k in obj) {\n\tprint($0k);\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a C-style for loop variable', () => {
		let src = cursors("for (let $1i = 0; i < 3; i++) {\n\tprint($0i);\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a catch parameter', () => {
		let src = cursors("try {} catch ($1e) {\n\tprint($0e);\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to the value variable of a two-variable for-in', () => {
		let src = cursors("let obj = {};\nfor (let k, $1v in obj) {\n\tprint($0v);\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);
	});

	it('a for-in without let assigns, so gd resolves to the real declaration', () => {
		// `for (x in …)` does not declare x; gd on the body x must reach `let x`.
		let src = cursors("let $1x = 0;\nfor (x in [1]) {\n\tprint($0x);\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);  // the `let x`, not the loop header
	});

	it('resolves an outer-function local captured by a nested closure', () => {
		let src = cursors("function outer() {\n\tlet $1cap = 1;\n\tfunction inner() {\n\t\treturn $0cap;\n\t}\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);  // outer's `let cap`
	});

	it('resolves a parameter that shadows a builtin name to the parameter', () => {
		// 'length' is a builtin; as a param it must resolve locally, not to global.d.uc
		let src = cursors("function f($1length) {\n\treturn $0length;\n}\n");
		let result = definitionAt(src);
		assert.match(point(URI, src.at[1]), result);                    // the param, not the builtin file
	});
});

// Property: for every local binder form, go-to-definition on a use site must
// resolve to a binding whose text is exactly the queried name. This fuzzes the
// whole binderIn/localScopeDef surface in one loop — the two-var and no-let
// for-in bugs would have been caught here by shrinking.
describe('definition — local binder identity (property)', () => {
	// $0 marks the use site.
	function buildBinderSource(shape, n) {
		if (shape === "let")     return cursors(sprintf("function f() {\n\tlet %s = 1;\n\t$0%s;\n}\n", n, n));
		if (shape === "block")   return cursors(sprintf("function f() {\n\t{\n\t\tlet %s = 1;\n\t\t$0%s;\n\t}\n}\n", n, n));
		if (shape === "for-in")  return cursors(sprintf("for (let %s in [1]) {\n\t$0%s;\n}\n", n, n));
		if (shape === "for-in2") return cursors(sprintf("for (let k, %s in obj) {\n\t$0%s;\n}\n", n, n));
		if (shape === "for-c")   return cursors(sprintf("for (let $0%s = 0; %s < 3; %s++) {\n\t0;\n}\n", n, n, n));
		if (shape === "catch")   return cursors(sprintf("try {} catch (%s) {\n\t$0%s;\n}\n", n, n));
		if (shape === "param")   return cursors(sprintf("function f(%s) {\n\t$0%s;\n}\n", n, n));
		// arrow bare param
		return cursors(sprintf("let g = %s => {\n\treturn $0%s;\n};\n", n, n));
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
			documents.open(URI, b.text, 1);
			dag.add(URI, b.text, documents.get(URI).tree);
			let r = definition(URI, documents.get(URI), b.at[0]);
			documents.close(URI);
			dag.remove(URI);
			assert.match(true, r !== null);
			assert.match(c.name, identAt(b.text, r.range.start));
			assert.match(r.range.start, r.range.end);
		});
});

describe('definition — member expression (record type, named import)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(PARSER_URI);
	});

	afterEach(() => dag.remove(PARSER_URI));

	it('jumps to record field key when cursor is on property of named import', () => {
		// A local record keeps the test self-contained, independent of any
		// module's layout.
		let src = cursors("let api = { $1greet: function(name) {}, bye: function() {} };\napi.$0greet;");
		let result = definitionImporting(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('returns null when property does not exist on the record', () => {
		let result = definitionImporting(cursors("let api = { greet: function() {} };\napi.$0doesNotExist;"));

		assert.match(null, result);
	});
});

describe('definition — chained member expression', () => {
	beforeEach(() => dag.init(_config));

	it('jumps to a field on a nested record (a.b.c where a.b is a record)', () => {
		// api.sub is a record with field 'go'
		let src = cursors("let api = { sub: { $1go: function() {}, stop: function() {} } };\napi.sub.$0go;");
		let result = definitionImporting(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('returns null when intermediate member does not exist', () => {
		let result = definitionImporting(cursors("let api = { sub: { go: function() {} } };\napi.missing.$0go;"));

		assert.match(null, result);
	});
});

describe('definition — brace-spanning template tag bindings', () => {
	it('jumps to a for-in loop variable declared in a brace-spanning tag', () => {
		let src = cursors("{% for (let $1x in [1]) { %}\n{{ $0x }}\n{% } %}\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a C-for initializer variable in a brace-spanning tag', () => {
		let src = cursors("{% for (let $1i = 0; i < 3; i++) { %}\n{{ $0i }}\n{% } %}\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a catch parameter in a brace-spanning try tag', () => {
		let src = cursors("{% try { %}\nx\n{% } catch ($1e) { %}\n{{ $0e }}\n{% } %}\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a parameter of a brace-spanning function tag', () => {
		let src = cursors("{% function f($1a, b) { %}\n{{ $0a }}\n{% } %}\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});

	it('jumps to a parameter of a colon-form function tag', () => {
		let src = cursors("{% function g($1a): %}\n{{ $0a }}\n{% endfunction %}\n");
		let result = definitionAt(src);

		assert.match(point(URI, src.at[1]), result);
	});
});
