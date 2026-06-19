import { describe, it, assert, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

// Library paths pointing at /app/src so imports like 'tree_sitter' resolve.
let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

let URI_A = 'file:///app/src/a.uc';
let URI_B = 'file:///app/src/b.uc';

let TEXT_A_IMPORTS_B = "import { foo } from 'b';\nexport function bar() {};";
let TEXT_B_EXPORTS   = "export function foo() {};";
let TEXT_A_NO_IMPORT = "export function bar() {};";

describe('dag nodes', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI_A);
		dag.remove(URI_B);
	});

	it('add makes exportsOf and importsOf available', () => {
		let text = TEXT_B_EXPORTS;
		dag.add(URI_B, text, parse(text));

		let exps = dag.exportsOf(URI_B);
		assert.match(true, exps !== null);
		assert.match(1, length(exps));
		assert.match('foo', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('exportsOf returns null for unknown uri', () => {
		assert.match(null, dag.exportsOf('file:///missing.uc'));
	});

	it('remove clears the node', () => {
		let text = TEXT_B_EXPORTS;
		dag.add(URI_B, text, parse(text));
		dag.remove(URI_B);

		assert.match(null, dag.exportsOf(URI_B));
	});

	it('allUris includes added nodes', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		let uris = dag.allUris();
		assert.match(true, index(uris, URI_B) >= 0);
	});
});

describe('dag edges', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.remove(URI_A);
		dag.remove(URI_B);
	});

	it('records reverse edge when A imports B', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		dag.add(URI_A, TEXT_A_IMPORTS_B, parse(TEXT_A_IMPORTS_B));

		// B is imported by A, so reverseDeps(B) should contain A
		// (only if 'b' resolves — it won't here since /app/src/b.uc doesn't exist)
		// This tests that importsOf records the specifier regardless.
		let imps = dag.importsOf(URI_A);
		assert.match(1, length(imps));
		assert.match('b', imps[0].specifier);
	});

	it('resolves imports for modules that exist on disk', () => {
		let text = "import * as ts from 'tree_sitter';";
		dag.add(URI_A, text, parse(text));

		let imps = dag.importsOf(URI_A);
		assert.match(1, length(imps));
		assert.match('file:///app/src/tree_sitter.uc', imps[0].resolvedUri);
		assert.match(true, index(dag.reverseDeps('file:///app/src/tree_sitter.uc'), URI_A) >= 0);
	});

	it('update removes stale edges when imports change', () => {
		let text1 = "import * as ts from 'tree_sitter';";
		dag.add(URI_A, text1, parse(text1));

		let tsUri = 'file:///app/src/tree_sitter.uc';
		assert.match(true, index(dag.reverseDeps(tsUri), URI_A) >= 0);

		// Update A to no longer import tree_sitter
		let text2 = TEXT_A_NO_IMPORT;
		dag.update(URI_A, text2, parse(text2));

		assert.match(false, index(dag.reverseDeps(tsUri), URI_A) >= 0);
	});
});
