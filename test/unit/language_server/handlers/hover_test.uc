import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { hover } from 'ucode_analyzer.language_server.handlers.hover';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as templates from 'ucode_analyzer.language_server.templates';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';
let PARSER_URI = fixture.uri('parser.uc');

// With selfSrcDir, so hover uses the built-in templates (not the fallback).
let _config = fixture.config();

dag.init(_config);

// Open the marked text and hover at $0.
function hoverAt(marked, config) {
	let src = cursors(marked);
	documents.open(URI, src.text, 1);
	return hover(documents.get(URI), src.at[0], config);
}

// Open the marked text with its imports in the DAG and hover at $0.
function hoverImporting(marked, config) {
	dag.addFromDisk(PARSER_URI);
	let src = cursors(marked);
	let doc = documents.open(URI, src.text, 1);
	dag.add(URI, doc.text, doc.tree);
	return hover(documents.get(URI), src.at[0], config);  // the scope map, now with the imports
}

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
	templates.resetCache();
});

describe('hover', () => {
	it('returns inferred type for an identifier', () => {
		let result = hoverAt('let $0x = 5;');

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
	});

	it('returns inferred type for an integer literal', () => {
		let result = hoverAt('let x = $05;');

		assert.match('object', type(result));
		assert.match(contains('int'), result.contents.value);
	});

	it('returns inferred type for a string literal', () => {
		let result = hoverAt("let s = $0'hello';");

		assert.match('object', type(result));
		assert.match(contains('string'), result.contents.value);
	});

	it('returns null for an anonymous token with no inferable type', () => {
		// nodeAtOffset returns the lexical_declaration → unknown
		assert.match(null, hoverAt('$0let x = 5;'));
	});

	it('returns null when position is beyond end of file', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		assert.match(null, hover(doc, { line: 99, character: 0 }));
	});

});

describe('hover — property_identifier in member expression', () => {
	// Hovering on 'parse' (property_identifier) should include its JSDoc, not just the type.
	it('shows JSDoc for a property of a namespace-import module', () => {
		let result = hoverImporting("import * as p from 'parser';\np.$0parse;");
		assert.match('object', type(result));
		// type string contains the name and signature
		assert.match(contains('parse'), result.contents.value);
		// JSDoc description is rendered (not just the type string)
		assert.match(contains('Parse source text'), result.contents.value);
	});
});

describe('hover — via templates (selfSrcDir set)', () => {
	it('function hover renders declaration-form signature and Parameters section', () => {
		let result = hoverImporting("import * as p from 'parser';\np.$0parse;", _config);

		assert.match('object', type(result));
		// Signature is declaration-form, not type-annotation form.
		assert.match(contains('function parse('), result.contents.value);
		assert.match(contains('**Parameters:**'), result.contents.value);
		// Each param must be on its own line.
		assert.match(contains('\n- `'), result.contents.value);
	});

	it('module hover renders module specifier from module template', () => {
		let result = hoverImporting("import * as p from 'parser';\n$0p;", _config);

		assert.match('object', type(result));
		// module template uses "module 'specifier'" format
		assert.match(contains("module 'parser'"), result.contents.value);
	});

	it('default hover renders code fence for primitive type', () => {
		let result = hoverAt('let $0x = 42;', _config);

		assert.match('object', type(result));
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
	});
});

describe('hover — parameter declaration site', () => {
	it('shows type and description from @param JSDoc when cursor is on the parameter', () => {
		let result = hoverAt("/**\n * @param {int} x — the multiplier\n */\nfunction double($0x) {}", _config);

		assert.match('object', type(result));
		assert.match(contains('x'), result.contents.value);
		assert.match(contains('int'), result.contents.value);
		assert.match(contains('multiplier'), result.contents.value);
	});

	it('returns null when cursor is on a parameter with no JSDoc', () => {
		assert.match(null, hoverAt("function noop($0x) {}", _config));
	});

	it('returns null when cursor is on a parameter not listed in @param tags', () => {
		assert.match(null, hoverAt("/** @param {int} a — first */\nfunction add(a, $0b) {}", _config));
	});

	it('shows type from @param for an exported function', () => {
		let result = hoverAt("/** @param {string} name — greeting target */\nexport function greet($0name) {};", _config);

		assert.match('object', type(result));
		assert.match(contains('name'), result.contents.value);
		assert.match(contains('string'), result.contents.value);
		assert.match(contains('greeting'), result.contents.value);
	});
});

describe('hover — doc comment tags', () => {
	// Hover shows docs of exports, so the functions under test are exported.
	function hoverText(marked) {
		let src = cursors(marked);
		dag.add(URI, src.text, documents.open(URI, src.text, 1).tree);
		let r = hover(documents.get(URI), src.at[0], _config);
		dag.remove(URI);
		return r?.contents?.value ?? '';
	}

	it('keeps a description that starts with a dash', () => {
		let v = hoverText("/** @returns {int} -1 on failure */\nexport function f() { return -1; };\n$0f;\n");
		assert.match(contains('-1 on failure'), v);
	});

	it('lists @see references', () => {
		let v = hoverText("/**\n * Opens.\n * @see close\n */\nexport function open() {};\n$0open;\n");
		assert.match(contains('**See:** close'), v);
	});

	it('types a member declared by @property', () => {
		let v = hoverText("/**\n * @typedef {Object} Conn\n * @property {string} host - Host name.\n */\n/** @type {Conn} */\nlet c = null;\nc.$0host;\n");
		assert.match(contains('host: string'), v);
		assert.match(contains('Host name.'), v);
	});

	it('lists a module\'s members', () => {
		let v = hoverText("import * as p from 'parser';\n$0p;\n");
		assert.match(contains('**Members:**'), v);
		assert.match(contains('- `parse`: `'), v);
	});

	it('types an exported const by its @type', () => {
		let v = hoverText("/** @type {string} */\nexport const NAME = f();\n$0NAME;\n");
		assert.match(contains('NAME: string'), v);
	});

	it('shows the doc of a local function', () => {
		let v = hoverText("/** Adds one. */\nfunction inc(x) { return x + 1; }\n$0inc;\n");
		assert.match(contains('Adds one.'), v);
	});

	it('shows the doc of a local const', () => {
		let v = hoverText("/** The limit. */\nconst MAX = 5;\n$0MAX;\n");
		assert.match(contains('The limit.'), v);
	});

	it('shows a parameter\'s @param description where it is used', () => {
		let v = hoverText("/** @param {int} n - How many. */\nfunction f(n) {\n  return $0n;\n}\n");
		assert.match(contains('How many.'), v);
	});

	it('does not give a parameter its function\'s description', () => {
		let v = hoverText("/** Doubles. @param {int} n */\nfunction f(n) {\n  return $0n;\n}\n");
		assert.match(-1, index(v, 'Doubles.'));
	});

	it('lists the members of a value typed by a named typedef', () => {
		let v = hoverText("/**\n * @typedef {{ host: string, port: int }} Conn\n */\n/** @type {Conn} */\nlet c = null;\n$0c;\n");
		assert.match(contains('c: Conn'), v);
		assert.match(contains('**Members:**'), v);
		assert.match(contains('- `port`: `int`'), v);
	});

	it('shows the signature of a value typed by a named function typedef', () => {
		assert.match(contains('function fmt(n: int): string'), hoverText("/** @typedef {(n: int) => string} Fmt */\n/** @type {Fmt} */\nlet fmt = null;\n$0fmt;\n"));
	});

	it('shows the parameters of an undocumented function', () => {
		assert.match(contains('function add(a, b)'), hoverText("function add(a, b) { return a + b; }\n$0add;\n"));
	});
});

