import { describe, it, assert, afterEach, starts_with } from 'utest';
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
	dag.addFromDisk(fixture.uri('settings.uc'));
	dag.addFromDisk(fixture.uri('legacy_mod.uc'));
	let src = cursors(marked);
	let doc = documents.open(URI, src.text, 1);
	dag.add(URI, doc.text, doc.tree);
	return hover(documents.get(URI), src.at[0], config);  // the scope map, now with the imports
}

// A markdown hover with `value`.
function md(value) {
	return { contents: { kind: 'markdown', value } };
}

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
	templates.resetCache();
});

describe('hover', () => {
	it('returns inferred type for an identifier', () => {
		assert.match(md("```ucode\nx: int\n```"), hoverAt('let $0x = 5;'));
	});

	it('returns inferred type for an integer literal', () => {
		assert.match(md("```ucode\n5: int\n```"), hoverAt('let x = $05;'));
	});

	it('returns inferred type for a string literal', () => {
		assert.match(md("```ucode\n'hello': string\n```"), hoverAt("let s = $0'hello';"));
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
		// the type string, then the JSDoc description (not just the type)
		assert.match(md("```ucode\nparse: (parser: object, source: string) => object\n```\n\nParse source text into a tree."), result);
	});
});

describe('hover — via templates (selfSrcDir set)', () => {
	it('function hover renders declaration-form signature and Parameters section', () => {
		let result = hoverImporting("import * as p from 'parser';\np.$0parse;", _config);

		// Declaration-form signature, not type-annotation form; one param per line.
		assert.match(md("```ucode\nfunction parse(parser: object, source: string): object\n```\n\n" +
			"Parse source text into a tree.\n\n**Parameters:**\n" +
			"- `parser`: `object` — A parser from newParser().\n" +
			"- `source`: `string` — The text to parse.\n"), result);
	});

	it('module hover renders module specifier from module template', () => {
		let result = hoverImporting("import * as p from 'parser';\n$0p;", _config);

		// module template uses "module 'specifier'" format
		assert.match(starts_with("```ucode\np: module 'parser'\n```\n"), result.contents.value);
	});

	it('default hover renders code fence for primitive type', () => {
		assert.match(md("```ucode\nx: int\n```"), hoverAt('let $0x = 42;', _config));
	});
});

describe('hover — parameter declaration site', () => {
	it('shows type and description from @param JSDoc when cursor is on the parameter', () => {
		let result = hoverAt("/**\n * @param {int} x — the multiplier\n */\nfunction double($0x) {}", _config);

		// only `-` is a JSDoc separator, so the em dash stays in the description
		assert.match(md("```ucode\nx: int\n```\n— the multiplier"), result);
	});

	it('returns null when cursor is on a parameter with no JSDoc', () => {
		assert.match(null, hoverAt("function noop($0x) {}", _config));
	});

	it('returns null when cursor is on a parameter not listed in @param tags', () => {
		assert.match(null, hoverAt("/** @param {int} a — first */\nfunction add(a, $0b) {}", _config));
	});

	it('shows type from @param for an exported function', () => {
		let result = hoverAt("/** @param {string} name — greeting target */\nexport function greet($0name) {};", _config);

		assert.match(md("```ucode\nname: string\n```\n— greeting target"), result);
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
		assert.match("```ucode\nfunction f(): int\n```\n\n**Returns:** -1 on failure\n", v);
	});

	it('lists @see references', () => {
		let v = hoverText("/**\n * Opens.\n * @see close\n */\nexport function open() {};\n$0open;\n");
		assert.match("```ucode\nfunction open(): ?\n```\n\nOpens.\n\n**See:** close\n", v);
	});

	it('types a member declared by @property', () => {
		let v = hoverText("/**\n * @typedef {Object} Conn\n * @property {string} host - Host name.\n */\n/** @type {Conn} */\nlet c = null;\nc.$0host;\n");
		assert.match("```ucode\nhost: string\n```\nHost name.", v);
	});

	it('lists a module\'s members', () => {
		let v = hoverText("import * as p from 'parser';\n$0p;\n");
		// Suspected bug: the description is newParser's doc comment (the first
		// statement of parser.uc), not a module doc; asserted as it is today.
		assert.match("```ucode\np: module 'parser'\n```\nCreate a parser for a language.\n**Members:**\n" +
			"- `newParser`: `(language: string) => object`\n" +
			"- `parse`: `(parser: object, source: string) => object`\n" +
			"- `rootNode`: `(tree: ?) => ?`\n" +
			"- `nodeType`: `(node: ?) => ?`\n" +
			"- `text`: `(node: object, source: string) => string`\n" +
			"- `parseString`: `(source: ?) => ?`", v);
	});

	it('types an exported const by its @type', () => {
		let v = hoverText("/** @type {string} */\nexport const NAME = f();\n$0NAME;\n");
		assert.match("```ucode\nNAME: string\n```", v);
	});

	it('shows the doc of a local function', () => {
		let v = hoverText("/** Adds one. */\nfunction inc(x) { return x + 1; }\n$0inc;\n");
		assert.match("```ucode\nfunction inc(x): ?\n```\n\nAdds one.\n", v);
	});

	it('shows the doc of a local const', () => {
		let v = hoverText("/** The limit. */\nconst MAX = 5;\n$0MAX;\n");
		assert.match("```ucode\nMAX: int\n```\nThe limit.", v);
	});

	it('shows a parameter\'s @param description where it is used', () => {
		let v = hoverText("/** @param {int} n - How many. */\nfunction f(n) {\n  return $0n;\n}\n");
		assert.match("```ucode\nn: int\n```\nHow many.", v);
	});

	it('does not give a parameter its function\'s description', () => {
		let v = hoverText("/** Doubles. @param {int} n */\nfunction f(n) {\n  return $0n;\n}\n");
		assert.match("```ucode\nn: int\n```", v);
	});

	it('lists the members of a value typed by a named typedef', () => {
		let v = hoverText("/**\n * @typedef {{ host: string, port: int }} Conn\n */\n/** @type {Conn} */\nlet c = null;\n$0c;\n");
		assert.match("```ucode\nc: Conn\n```\n\n**Members:**\n- `host`: `string`\n- `port`: `int`\n", v);
	});

	it('shows the signature of a value typed by a named function typedef', () => {
		assert.match("```ucode\nfunction fmt(n: int): string\n```\n", hoverText("/** @typedef {(n: int) => string} Fmt */\n/** @type {Fmt} */\nlet fmt = null;\n$0fmt;\n"));
	});

	it('shows the parameters of an undocumented function', () => {
		assert.match("```ucode\nfunction add(a, b): ?\n```\n", hoverText("function add(a, b) { return a + b; }\n$0add;\n"));
	});
});

describe('hover — imports whose docs carry no tags', () => {
	function value(marked) {
		let r = hoverImporting(marked, _config);
		dag.remove(URI);
		return r?.contents?.value ?? '';
	}

	it('types an imported const from its literal and shows its doc', () => {
		let v = value("import { VERSION } from 'settings';\n$0VERSION;\n");
		assert.match("```ucode\nVERSION: int\n```\nThe protocol version.", v);
	});

	it('shows the doc of an imported const of unknown type', () => {
		let v = value("import { TIMEOUT } from 'settings';\n$0TIMEOUT;\n");
		assert.match("```ucode\nTIMEOUT: ?\n```\nThe timeout, in seconds.", v);
	});

	it('names the parameters of an imported function without @param tags', () => {
		let v = value("import { joinNames } from 'settings';\n$0joinNames;\n");
		assert.match("```ucode\nfunction joinNames(first, second): ?\n```\n\nJoins two names.\n", v);
	});

	it('types an exported const bound to a function, rest parameter included', () => {
		assert.match("```ucode\nfunction pick(list, ...rest: list<?>): ?\n```\n", value("import { pick } from 'settings';\n$0pick;\n"));
		let v = value("import * as p from 'parser';\np.$0rootNode;\n");
		assert.match("```ucode\nfunction rootNode(tree): ?\n```\n\nThe root node of a tree.\n", v);
	});

	it('names the parameters of a legacy module member', () => {
		assert.match("```ucode\nfunction greet(name): ?\n```\n", value("let m = require('legacy_mod');\nm.$0greet;\n"));
	});

	it('still shows nothing for an undocumented local of unknown type', () => {
		assert.match(null, hoverAt("let x = int('3');\n$0x;\n", _config));
	});
});
