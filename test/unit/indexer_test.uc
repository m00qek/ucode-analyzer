import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { extractExports, extractImports, resolveModule } from 'ucode_language_server.indexer';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
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

		assert.match(2, length(imps));
		assert.match('x', imps[0].specifier);
		assert.match('y', imps[1].specifier);
	});

	it('returns empty list when no imports', () => {
		let text = 'let x = 5;';
		let imps = extractImports(text, parse(text));

		assert.match(0, length(imps));
	});
});

describe('indexer.resolveModule', () => {
	it('resolves dot-separated module to slash path', () => {
		let uri = resolveModule('ucode_language_server.documents', ['/app/src'], '/app');
		assert.match('file:///app/src/ucode_language_server/documents.uc', uri);
	});

	it('resolves simple module name', () => {
		let uri = resolveModule('tree_sitter', ['/app/src'], '/app');
		assert.match('file:///app/src/tree_sitter.uc', uri);
	});

	it('resolves relative library path against workspace dir', () => {
		let uri = resolveModule('tree_sitter', ['src'], '/app');
		assert.match('file:///app/src/tree_sitter.uc', uri);
	});

	it('returns null for unknown module', () => {
		let uri = resolveModule('nonexistent.module', ['/app/src'], '/app');
		assert.match(null, uri);
	});
});
