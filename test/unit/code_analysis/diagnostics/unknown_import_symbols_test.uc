import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unknownImportSymbols } from 'ucode_analyzer.code_analysis.diagnostics.unknown_import_symbols';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';

let URI    = 'file:///test.uc';
let TS_URI = 'file:///app/src/tree_sitter.uc';
let DE_URI = 'file:///app/test/fixtures/default_export.uc';

let _config = {
	workspaceDir: '/app',
	selfSrcDir: '/app/src/ucode_analyzer',
	workspace: { libraryPaths: ['src', 'test'] },
};

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(TS_URI);
	dag.remove(DE_URI);
});

describe('diagnostics — unknown import symbols', () => {
	it('returns empty list when all named imports exist in the module', () => {
		let text = "import { parse } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports an error for a named import that is not exported', () => {
		let text = "import { noSuchExport } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let diags = unknownImportSymbols(URI, documents.get(URI));

		assert.match(1, length(diags));
		assert.match(1, diags[0].severity);
		assert.match(contains('noSuchExport'), diags[0].message);
	});

	it('highlights the remote name node, not the whole import statement', () => {
		let text = "import { noSuchExport } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let r = unknownImportSymbols(URI, documents.get(URI))[0].range;

		assert.match(0, r.start.line);
		// 'noSuchExport' starts after "import { " (9 chars)
		assert.match(true, r.start.character >= 9);
	});

	it('reports one error per bad symbol when multiple are wrong', () => {
		let text = "import { bad1, bad2 } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(2, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('does not report an error for namespace imports (import * as x)', () => {
		let text = "import * as ts from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('does not report errors for an unresolvable module (handled by unknownImports)', () => {
		let text = "import { anything } from 'no_such_module';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('accepts renamed imports when the remote name exists', () => {
		// import { parse as p } from 'tree_sitter' — remote 'parse' exists
		let text = "import { parse as p } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports error for renamed import when the remote name does not exist', () => {
		let text = "import { noSuch as local } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let diags = unknownImportSymbols(URI, documents.get(URI));

		assert.match(1, length(diags));
		assert.match(contains('noSuch'), diags[0].message);
	});

	it('accepts a default import of a module with `export default`', () => {
		let text = "import x from 'fixtures.default_export';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('accepts `default as` and quoted names that the module exports', () => {
		let text = "import { default as e, \"b-c\" as d } from 'fixtures.default_export';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports a default import of a module without a default export', () => {
		let text = "import x from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		let diags = unknownImportSymbols(URI, documents.get(URI));
		assert.match(1, length(diags));
		assert.match(contains("'default'"), diags[0].message);
		assert.match(7, diags[0].range.start.character);   // on `x`
	});
});
