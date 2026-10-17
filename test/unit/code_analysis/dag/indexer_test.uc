import { describe, it, assert, prop, gen } from 'utest';
import * as ts from 'tree_sitter';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { extractExports, extractImports, extractModuleDoc, extractVersions, resolveModule } from 'ucode_analyzer.code_analysis.dag.indexer';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

// Template snippets go through mode.parse so they get the markup grammar.
function parseTpl(text) {
	return mode.parse(text);
}

describe('indexer.extractExports', () => {
	it('extracts exported function', () => {
		let text = 'export function foo(x) { return x; };';
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match('foo', exps[0].name);
		assert.match('function', exps[0].kind);
		assert.match(null, exps[0].doc);
	});

	it('extracts exported const', () => {
		let text = 'export const BAR = 42;';
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match('BAR', exps[0].name);
		assert.match('const', exps[0].kind);
	});

	it('extracts exported let', () => {
		let text = 'export let baz = null;';
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match('baz', exps[0].name);
		assert.match('let', exps[0].kind);
	});

	it('extracts multiple exports', () => {
		let text = 'export function a() {};\nexport const b = 1;\nexport let c = 2;';
		let exps = extractExports(text, parse(text));

		assert.match(3, length(exps));
		assert.match('a', exps[0].name);
		assert.match('b', exps[1].name);
		assert.match('c', exps[2].name);
	});

	it('ignores non-exported declarations', () => {
		let text = 'function foo() {}\nconst bar = 1;';
		let exps = extractExports(text, parse(text));

		assert.match(0, length(exps));
	});

	it('populates doc when a JSDoc comment precedes the export', () => {
		let text = "/** @param {string} x @returns {int} */\nexport function foo(x) {};";
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match(true, exps[0].doc !== null);
		assert.match({ kind: 'primitive', name: 'int' }, exps[0].doc.returns.type);
		assert.match('x', exps[0].doc.params[0].name);
	});

	it('doc is null when no JSDoc comment precedes the export', () => {
		let text = '// not a jsdoc\nexport function bar() {};';
		let exps = extractExports(text, parse(text));

		assert.match(null, exps[0].doc);
	});

	// Regression (tree-sitter-ucode < v0.8.0): the automatic-semicolon token
	// swallowed an own-line comment that followed a brace-terminated statement
	// with no explicit `;` (e.g. `function f() {}`), so the comment node vanished
	// into the preceding declaration and docBefore found nothing for the next
	// export. Fixed upstream in v0.8.0; guard it here since doc association relies
	// on it.
	it('associates a doc comment after a brace-terminated statement with the next export', () => {
		let text = "function f() { return 1; }\n/** @returns {int} */\nexport const a = 1;\n";
		let exps = extractExports(text, parse(text));

		// f is not exported, so `a` is the only export.
		assert.match(1, length(exps));
		assert.match('a', exps[0].name);
		assert.match(true, exps[0].doc !== null);
		assert.match({ kind: 'primitive', name: 'int' }, exps[0].doc.returns.type);
	});

	it('associates a block doc comment between a semicolon-less let and the next export', () => {
		let text = "let x = 1\n/** @returns {string} */\nexport function g() {}\n";
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match('g', exps[0].name);
		assert.match(true, exps[0].doc !== null);
		assert.match({ kind: 'primitive', name: 'string' }, exps[0].doc.returns.type);
	});

	it('extracts memberRef for member-expression re-export', () => {
		let text = 'export const describe = dsl.describe;';
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		assert.match('describe', exps[0].name);
		assert.match({ alias: 'dsl', member: 'describe' }, exps[0].memberRef);
	});

	it('memberRef is null for plain value exports', () => {
		let text = 'export const X = 42;';
		let exps = extractExports(text, parse(text));

		assert.match(null, exps[0].memberRef);
	});

	it('properties is null for non-object exports', () => {
		let text = 'export const X = 42;';
		let exps = extractExports(text, parse(text));
		assert.match(null, exps[0].properties);
	});

	it('populates properties for object-literal exports with function-expression values', () => {
		let text = "export const ns = { /** @param {string} s @returns {int} */ greet: function(s) {}, go: function() {} };";
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		let props = exps[0].properties;
		assert.match([['greet', 'function'], ['go', 'function']], map(props, (p) => [p.name, p.kind]));
		assert.match(['s'], map(props[0].doc.params, (p) => p.name));
		assert.match(null, props[1].doc);
	});

	it('populates properties for object-literal exports with identifier values (resolves local decl)', () => {
		let text = "/** @param {string} s @returns {int} */ function greet(s) { return 0; }\nexport const ns = { greet: greet };";
		let exps = extractExports(text, parse(text));

		let props = exps[0].properties;
		assert.match([['greet', 'function']], map(props, (p) => [p.name, p.kind]));
		assert.match(['s'], map(props[0].doc.params, (p) => p.name));
	});

	it('populates nested properties for object-literal exports with object values', () => {
		let text = "export const api = { /** @param {string} s @returns {int} */ fn: function(s) {}, sub: { /** @param {string} x */ go: function(x) {} } };";
		let exps = extractExports(text, parse(text));

		assert.match(1, length(exps));
		let props = exps[0].properties;
		assert.match([['fn', 'function'], ['sub', 'object']], map(props, (p) => [p.name, p.kind]));
		let subProps = props[1].properties;
		assert.match([['go', 'function']], map(subProps, (p) => [p.name, p.kind]));
		assert.match(['x'], map(subProps[0].doc.params, (p) => p.name));
	});

	it('stores position for an exported function', () => {
		let src = cursors('export function $0foo(x) { return x; };');
		let exps = extractExports(src.text, parse(src.text));

		assert.match(src.at[0], exps[0].position);
	});

	it('stores position for an exported const', () => {
		let src = cursors('export const $0BAR = 42;');
		let exps = extractExports(src.text, parse(src.text));

		assert.match(src.at[0], exps[0].position);
	});

	it('stores position across multiple lines', () => {
		let src = cursors('export function $0a() {};\nexport const $1b = 1;');
		let exps = extractExports(src.text, parse(src.text));

		assert.match(src.at[0], exps[0].position);
		assert.match(src.at[1], exps[1].position);
	});

	it('stores position for export-clause exports', () => {
		let src = cursors('function $0greet() {}\nexport { greet };');
		let exps = extractExports(src.text, parse(src.text));

		assert.match('greet', exps[0].name);
		// the local declaration, not the export clause
		assert.match(src.at[0], exps[0].position);
	});

	it('names an export-clause default export `default`', () => {
		let text = 'function greet() {}\nexport { greet as default };';
		let exps = extractExports(text, parse(text));
		assert.match(1, length(exps));
		assert.match('default', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('names an `export default` value `default`', () => {
		let text = "export default { k: 2 };\n";
		let exps = extractExports(text, parse(text));
		assert.match(1, length(exps));
		assert.match('default', exps[0].name);
		assert.match(['k'], map(exps[0].properties, (p) => p.name));
	});

	it('types an `export default` function expression as a function', () => {
		let text = "export default (function(a) { return a; });\n";
		let exps = extractExports(text, parse(text));
		assert.match('default', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('names a quoted export-clause alias without its quotes', () => {
		let text = "let a = 1;\nexport { a as \"b-c\" };\n";
		let exps = extractExports(text, parse(text));
		assert.match(['b-c'], map(exps, (e) => e.name));
	});

	it('extracts memberRef through optional chaining', () => {
		let text = "import * as m from 'x';\nexport const c = m?.b;\n";
		let exps = extractExports(text, parse(text));
		assert.match({ alias: 'm', member: 'b' }, exps[0].memberRef);
	});

	it('reads an export after a comment', () => {
		let text = "export /* c */ function f() {};\n";
		let exps = extractExports(text, parse(text));
		assert.match(['f'], map(exps, (e) => e.name));
	});

	// ── legacy module pattern: top-level `return { ... }` (ucode require shape) ──
	it('surfaces top-level return-object fields as exports', () => {
		let text = "return {\n\tread_state: function() { return 1; },\n\tversion: 2\n};\n";
		let exps = extractExports(text, parse(text));
		assert.match([['read_state', 'function'], ['version', 'value']], map(exps, (e) => [e.name, e.kind]));
	});

	it('types a return-object function field as a function export', () => {
		let text = "return {\n\tread_state: function() { return 1; }\n};\n";
		let exps = extractExports(text, parse(text));
		assert.match('read_state', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('records the field key position for a return-object export', () => {
		let src = cursors("return {\n\t$0read_state: function() {}\n};\n");
		let exps = extractExports(src.text, parse(src.text));
		assert.match(src.at[0], exps[0].position);
	});

	it('lets an ES export take precedence over a same-named return field', () => {
		let text = "export function foo() {};\nreturn { foo: 1 };\n";
		let exps = extractExports(text, parse(text));
		// the ES export is pushed first, so it is the first match by name
		assert.match('foo', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('ignores a non-object top-level return', () => {
		let text = "let x = 1;\nreturn x;\n";
		let exps = extractExports(text, parse(text));
		assert.match(0, length(exps));
	});

	it('does not duplicate a name exported by both ES export and the return object', () => {
		let text = "export function foo() {};\nreturn { foo, bar: 1 };\n";
		let exps = extractExports(text, parse(text));
		// foo once, as the ES export (pushed first)
		assert.match([['foo', 'function'], ['bar', 'value']], map(exps, (e) => [e.name, e.kind]));
	});

	it('does not surface a return object nested inside a function', () => {
		let text = "function f() { return { secret: 1 }; }\nexport { f };\n";
		let names = map(extractExports(text, parse(text)), (e) => e.name);
		assert.match(['f'], names);
	});

	it('takes only the first top-level return object as the module value', () => {
		let text = "return { a: 1 };\nreturn { b: 2 };\n";
		let names = map(extractExports(text, parse(text)), (e) => e.name);
		assert.match(['a'], names);
	});

	it('surfaces a shorthand field of the return object', () => {
		let text = "let helper = 1;\nreturn { helper };\n";
		let names = map(extractExports(text, parse(text)), (e) => e.name);
		assert.match(['helper'], names);
	});

	// A return object is only the module's exports at the top level. Nested at any
	// depth inside a function it is a return value, never an export.
	prop("a return object nested inside function(s) yields no exports",
		gen.int(1, 4),
		(depth) => {
			let src = "return { a: 1, b: 2 };";
			for (let i = 0; i < depth; i++) src = sprintf("function f%d() { %s }", i, src);
			let names = map(extractExports(src, parse(src)), (e) => e.name);
			assert.match([], names);
		});
});

describe('indexer.extractImports', () => {
	it('extracts named import', () => {
		let text = "import { foo, bar } from 'mod.name';";
		let imps = extractImports(text, parse(text));

		assert.match(1, length(imps));
		assert.match('mod.name', imps[0].specifier);
		assert.match(['foo', 'bar'], imps[0].symbols);
		assert.match(null, imps[0].alias);
		assert.match(null, imps[0].resolvedUri);
	});

	it('extracts a default import as a rename of `default`', () => {
		let text = "import x, { y } from 'mod.name';";
		let imps = extractImports(text, parse(text));
		assert.match(1, length(imps));
		assert.match(['x', 'y'], imps[0].symbols);
		assert.match({ x: 'default' }, imps[0].renames);
	});

	it('extracts a default import next to a namespace import', () => {
		let text = "import x, * as ns from 'mod.name';";
		let imps = extractImports(text, parse(text));
		assert.match([
			{ specifier: 'mod.name', symbols: ['*'], alias: 'ns', resolvedUri: null },
			{ specifier: 'mod.name', symbols: ['x'], renames: { x: 'default' }, alias: null, resolvedUri: null },
		], imps);
	});

	it('extracts namespace import', () => {
		let text = "import * as ns from 'mod.name';";
		let imps = extractImports(text, parse(text));

		assert.match(1, length(imps));
		assert.match('mod.name', imps[0].specifier);
		assert.match(['*'], imps[0].symbols);
		assert.match('ns', imps[0].alias);
	});

	it('extracts multiple imports', () => {
		let text = "import { a } from 'x';\nimport * as b from 'y';";
		let imps = extractImports(text, parse(text));

		assert.match([
			{ specifier: 'x', symbols: ['a'], renames: {}, alias: null, resolvedUri: null },
			{ specifier: 'y', symbols: ['*'], alias: 'b', resolvedUri: null },
		], imps);
	});

	it('returns empty list when no imports', () => {
		let text = 'let x = 5;';
		let imps = extractImports(text, parse(text));

		assert.match(0, length(imps));
	});
});

describe('indexer.resolveModule', () => {
	let WS = fixture.WORKSPACE;

	it('resolves dot-separated module to slash path', () => {
		let uri = resolveModule('reexport.wrapper', [WS], WS);
		assert.match(fixture.uri('reexport/wrapper.uc'), uri);
	});

	it('resolves simple module name', () => {
		let uri = resolveModule('parser', [WS], WS);
		assert.match(fixture.uri('parser.uc'), uri);
	});

	it('resolves relative library path against workspace dir', () => {
		let uri = resolveModule('deep', ['reexport'], WS);
		assert.match(fixture.uri('reexport/deep.uc'), uri);
	});

	it('returns null for unknown module', () => {
		let uri = resolveModule('nonexistent.module', [WS], WS);
		assert.match(null, uri);
	});

	// The bundled declarations.
	it('resolves declaration file directly under lib path (no extra declarations/ prefix)', () => {
		// When libPath itself is a declarations dir, .d.uc lives at absLib/<name>.d.uc
		let uri = resolveModule('uci', ['/app/src/ucode_analyzer/declarations'], WS);
		assert.match('file:///app/src/ucode_analyzer/declarations/uci.d.uc', uri);
	});

	it('resolves dot-separated declaration file directly under lib path', () => {
		let uri = resolveModule('uci', ['/app/src/ucode_analyzer'], WS);
		assert.match('file:///app/src/ucode_analyzer/declarations/uci.d.uc', uri);
	});
});

describe('indexer.extractModuleDoc', () => {
	it('returns null when file has no leading doc comment', () => {
		let text = 'export function foo() {};';
		assert.match(null, extractModuleDoc(text, parse(text)));
	});

	it('returns null when leading comment has no description', () => {
		let text = '/** @param {string} x */\nexport function foo(x) {};';
		assert.match(null, extractModuleDoc(text, parse(text)));
	});

	it('returns the parsed doc for a leading /** */ with a description', () => {
		let text = '/**\n * Module for doing things.\n * @module mymod\n */\nexport function foo() {};';
		let doc = extractModuleDoc(text, parse(text));
		assert.match(true, doc !== null);
		assert.match('Module for doing things.', doc.description);
	});

	it('returns null when the first comment is a line comment', () => {
		let text = '// not a jsdoc\nexport function foo() {};';
		assert.match(null, extractModuleDoc(text, parse(text)));
	});
});

describe('indexer.extractVersions', () => {
	it('parses a single version', () => {
		let text = '// Source: https://github.com/jow-/ucode\n// Versions: 2026.01.16~85922056\n';
		assert.match(['2026.01.16~85922056'], extractVersions(text));
	});

	it('parses multiple comma-separated versions', () => {
		let text = '// Source: https://example.com\n// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056\n';
		assert.match(['2025.07.18~3f64c808', '2026.01.16~85922056'], extractVersions(text));
	});

	it('trims whitespace around each version token', () => {
		let text = '// Versions:  v1 ,  v2 ,  v3 \n';
		assert.match(['v1', 'v2', 'v3'], extractVersions(text));
	});

	it('returns null when no Versions comment is present', () => {
		let text = '// Source: https://example.com\n/** @module foo */\nexport function bar() {};\n';
		assert.match(null, extractVersions(text));
	});

	it('returns null for empty file', () => {
		assert.match(null, extractVersions(''));
	});

	it('only looks in first 512 bytes', () => {
		let padding = '';
		for (let i = 0; i < 513; i++) padding += 'x';
		let text = padding + '\n// Versions: 2026.01.16~85922056\n';
		assert.match(null, extractVersions(text));
	});
});

describe('indexer — template mode (imports/exports inside {% %})', () => {
	it('extracts an import declared inside a statement tag', () => {
		let text = "{% import { helper } from 'lib.util'; %}\n<p>hi</p>\n";
		let imps = extractImports(text, parseTpl(text));
		assert.match([
			{ specifier: 'lib.util', symbols: ['helper'], renames: {}, alias: null, resolvedUri: null },
		], imps);
	});

	it('extracts a namespace import inside a statement tag', () => {
		let text = "{% import * as u from 'lib.util'; %}\n";
		let imps = extractImports(text, parseTpl(text));
		assert.match(1, length(imps));
		assert.match('u', imps[0].alias);
	});

	it('extracts an exported function declared inside a statement tag', () => {
		let text = "{% export function render(x) { return x; }; %}\n<div></div>\n";
		let exps = extractExports(text, parseTpl(text));
		assert.match(1, length(exps));
		assert.match('render', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('extracts an exported const inside a statement tag', () => {
		let text = "{% export const TITLE = 'Home'; %}\n";
		let exps = extractExports(text, parseTpl(text));
		assert.match(1, length(exps));
		assert.match('TITLE', exps[0].name);
		assert.match('const', exps[0].kind);
	});

	it('resolves an export clause against a local decl in another tag', () => {
		// localDeclInfo must also descend through statement tags.
		let text = "{% function greet() {} %}\n{% export { greet }; %}\n";
		let exps = extractExports(text, parseTpl(text));
		assert.match(1, length(exps));
		assert.match('greet', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('finds imports and exports across separate tags in one template', () => {
		let text = "{% import { a } from 'm'; %}\n" +
		           "text\n" +
		           "{% export const B = a; %}\n";
		assert.match([
			{ specifier: 'm', symbols: ['a'], renames: {}, alias: null, resolvedUri: null },
		], extractImports(text, parseTpl(text)));
		assert.match([['B', 'const', 'a']],
			map(extractExports(text, parseTpl(text)), (e) => [e.name, e.kind, e.localRef]));
	});
});
