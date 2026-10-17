import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { hover } from 'ucode_analyzer.language_server.handlers.hover';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as templates from 'ucode_analyzer.language_server.templates';

let URI = 'file:///test.uc';

let _config = { workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src'] } };
// Config with selfSrcDir so hover uses the built-in templates (not the fallback).
let _full_config = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] }, selfSrcDir: '/app/src/ucode_analyzer' };

dag.init(_config);

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
	templates.resetCache();
});

describe('hover', () => {
	it('returns inferred type for an identifier', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 4 is 'x'; buildScope processes the declaration → x: int
		let result = hover(doc, { line: 0, character: 4 });

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
	});

	it('returns inferred type for an integer literal', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 8 is the '5' literal
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(contains('int'), result.contents.value);
	});

	it('returns inferred type for a string literal', () => {
		documents.open(URI, "let s = 'hello';", 1);
		let doc = documents.get(URI);

		// character 8 is the opening quote of 'hello'
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(contains('string'), result.contents.value);
	});

	it('returns null for an anonymous token with no inferable type', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 0 is 'l' in 'let'; nodeAtOffset returns lexical_declaration → unknown
		let result = hover(doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null when position is beyond end of file', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		assert.match(null, hover(doc, { line: 99, character: 0 }));
	});

});

describe('hover — property_identifier in member expression', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	// `import * as ts from 'tree_sitter'; ts.parse;`
	// Hovering on 'parse' (property_identifier) should include its JSDoc, not just the type.
	it('shows JSDoc for a property of a namespace-import module', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts.parse;";
		let doc = documents.open(URI, text, 1);
		// Register the document in the DAG so importsOf resolves the namespace import.
		dag.add(URI, doc.text, doc.tree);
		doc = documents.get(URI);  // builds the scope map, now with the imports
		// line 1, character 3 → 'p' of 'parse'
		let result = hover(doc, { line: 1, character: 3 });
		assert.match('object', type(result));
		// type string contains the name and signature
		assert.match(contains('parse'), result.contents.value);
		// JSDoc description is rendered (not just the type string)
		assert.match(contains('Parse source text'), result.contents.value);
	});
});

describe('hover — via templates (selfSrcDir set)', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	it('function hover renders declaration-form signature and Parameters section', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts.parse;";
		let doc = documents.open(URI, text, 1);
		dag.add(URI, doc.text, doc.tree);
		doc = documents.get(URI);  // builds the scope map, now with the imports

		// line 1, character 3 → 'parse' property_identifier
		let result = hover(doc, { line: 1, character: 3 }, _full_config);

		assert.match('object', type(result));
		// Signature is declaration-form, not type-annotation form.
		assert.match(contains('function parse('), result.contents.value);
		assert.match(contains('**Parameters:**'), result.contents.value);
		// Each param must be on its own line.
		assert.match(contains('\n- `'), result.contents.value);
	});

	it('module hover renders module specifier from module template', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts;";
		let doc = documents.open(URI, text, 1);
		dag.add(URI, doc.text, doc.tree);
		doc = documents.get(URI);  // builds the scope map, now with the imports

		// line 1, character 0 → 'ts' namespace alias
		let result = hover(doc, { line: 1, character: 0 }, _full_config);

		assert.match('object', type(result));
		// module template uses "module 'specifier'" format
		assert.match(contains("module 'tree_sitter'"), result.contents.value);
	});

	it('default hover renders code fence for primitive type', () => {
		let text = "let x = 42;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		dag.add(URI, doc.text, doc.tree);

		let result = hover(doc, { line: 0, character: 4 }, _full_config);

		assert.match('object', type(result));
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
	});
});

describe('hover — parameter declaration site', () => {
	it('shows type and description from @param JSDoc when cursor is on the parameter', () => {
		// @param {int} x — the multiplier
		// function double(x) {}  ← cursor on 'x' at col 16
		let text = "/**\n * @param {int} x — the multiplier\n */\nfunction double(x) {}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		let result = hover(doc, { line: 3, character: 16 }, _full_config);

		assert.match('object', type(result));
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
		assert.match(contains('multiplier'), result.contents.value);
	});

	it('returns null when cursor is on a parameter with no JSDoc', () => {
		let text = "function noop(x) {}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// cursor on 'x' at col 14
		let result = hover(doc, { line: 0, character: 14 }, _full_config);

		assert.match(null, result);
	});

	it('returns null when cursor is on a parameter not listed in @param tags', () => {
		let text = "/** @param {int} a — first */\nfunction add(a, b) {}";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// cursor on 'b' at line 1 col 16
		let result = hover(doc, { line: 1, character: 16 }, _full_config);

		assert.match(null, result);
	});

	it('shows type from @param for an exported function', () => {
		let text = "/** @param {string} name — greeting target */\nexport function greet(name) {};";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);

		// cursor on 'name' at line 1 col 22
		let result = hover(doc, { line: 1, character: 22 }, _full_config);

		assert.match('object', type(result));
		assert.match(contains('name'), result.contents.value);
		assert.match(contains('string'), result.contents.value);
		assert.match(contains('greeting'), result.contents.value);
	});
});

describe('hover — doc comment tags', () => {
	// Hover shows docs of exports, so the functions under test are exported.
	function hoverText(text, line, character) {
		dag.add(URI, text, documents.open(URI, text, 1).tree);
		let r = hover(documents.get(URI), { line, character }, _full_config);
		dag.remove(URI);
		return r?.contents?.value ?? '';
	}

	it('keeps a description that starts with a dash', () => {
		let v = hoverText("/** @returns {int} -1 on failure */\nexport function f() { return -1; };\nf;\n", 2, 0);
		assert.match(contains('-1 on failure'), v);
	});

	it('lists @see references', () => {
		let v = hoverText("/**\n * Opens.\n * @see close\n */\nexport function open() {};\nopen;\n", 5, 0);
		assert.match(contains('**See:** close'), v);
	});

	it('types a member declared by @property', () => {
		let text = "/**\n * @typedef {Object} Conn\n * @property {string} host - Host name.\n */\n/** @type {Conn} */\nlet c = null;\nc.host;\n";
		let v = hoverText(text, 6, 3);
		assert.match(contains('host: string'), v);
		assert.match(contains('Host name.'), v);
	});

	it('lists a module\'s members', () => {
		let v = hoverText("import * as ts from 'tree_sitter';\nts;\n", 1, 0);
		assert.match(contains('**Members:**'), v);
		assert.match(contains('- `parse`: `'), v);
	});

	it('types an exported const by its @type', () => {
		let v = hoverText("/** @type {string} */\nexport const NAME = f();\nNAME;\n", 2, 0);
		assert.match(contains('NAME: string'), v);
	});

	it('shows the doc of a local function', () => {
		let v = hoverText("/** Adds one. */\nfunction inc(x) { return x + 1; }\ninc;\n", 2, 0);
		assert.match(contains('Adds one.'), v);
	});

	it('shows the doc of a local const', () => {
		let v = hoverText("/** The limit. */\nconst MAX = 5;\nMAX;\n", 2, 0);
		assert.match(contains('The limit.'), v);
	});

	it('shows a parameter\'s @param description where it is used', () => {
		let v = hoverText("/** @param {int} n - How many. */\nfunction f(n) {\n  return n;\n}\n", 2, 9);
		assert.match(contains('How many.'), v);
	});

	it('does not give a parameter its function\'s description', () => {
		let v = hoverText("/** Doubles. @param {int} n */\nfunction f(n) {\n  return n;\n}\n", 2, 9);
		assert.match(-1, index(v, 'Doubles.'));
	});

	it('lists the members of a value typed by a named typedef', () => {
		let text = "/**\n * @typedef {{ host: string, port: int }} Conn\n */\n/** @type {Conn} */\nlet c = null;\nc;\n";
		let v = hoverText(text, 5, 0);
		assert.match(contains('c: Conn'), v);
		assert.match(contains('**Members:**'), v);
		assert.match(contains('- `port`: `int`'), v);
	});

	it('shows the signature of a value typed by a named function typedef', () => {
		let text = "/** @typedef {(n: int) => string} Fmt */\n/** @type {Fmt} */\nlet fmt = null;\nfmt;\n";
		assert.match(contains('function fmt(n: int): string'), hoverText(text, 3, 0));
	});

	it('shows the parameters of an undocumented function', () => {
		assert.match(contains('function add(a, b)'), hoverText("function add(a, b) { return a + b; }\nadd;\n", 1, 0));
	});
});

