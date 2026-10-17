import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unknownImportSymbols } from 'ucode_analyzer.code_analysis.diagnostics.unknown_import_symbols';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI        = 'file:///test.uc';
let PARSER_URI = fixture.uri('parser.uc');
let DE_URI     = fixture.uri('default_export.uc');

let _config = fixture.config();

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(PARSER_URI);
	dag.remove(DE_URI);
});

describe('diagnostics — unknown import symbols', () => {
	it('returns empty list when all named imports exist in the module', () => {
		let text = "import { parse } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports an error for a named import that is not exported', () => {
		let text = "import { noSuchExport } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let diags = unknownImportSymbols(URI, documents.get(URI));

		assert.match(1, length(diags));
		assert.match(1, diags[0].severity);
		assert.match(contains('noSuchExport'), diags[0].message);
	});

	it('highlights the remote name node, not the whole import statement', () => {
		let src = cursors("import { $0noSuchExport$1 } from 'parser';\n");
		documents.open(URI, src.text, 1);
		dag.add(URI, src.text, documents.get(URI).tree);

		let r = unknownImportSymbols(URI, documents.get(URI))[0].range;

		assert.match({ start: src.at[0], end: src.at[1] }, r);
	});

	it('reports one error per bad symbol when multiple are wrong', () => {
		let text = "import { bad1, bad2 } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(2, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('does not report an error for namespace imports (import * as x)', () => {
		let text = "import * as ts from 'parser';\n";
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
		// import { parse as p } from 'parser' — remote 'parse' exists
		let text = "import { parse as p } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports error for renamed import when the remote name does not exist', () => {
		let text = "import { noSuch as local } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let diags = unknownImportSymbols(URI, documents.get(URI));

		assert.match(1, length(diags));
		assert.match(contains('noSuch'), diags[0].message);
	});

	it('accepts a default import of a module with `export default`', () => {
		let text = "import x from 'default_export';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('accepts `default as` and quoted names that the module exports', () => {
		let text = "import { default as e, \"b-c\" as d } from 'default_export';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);
		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('reports a default import of a module without a default export', () => {
		let src = cursors("import $0x$1 from 'parser';\n");
		documents.open(URI, src.text, 1);
		dag.add(URI, src.text, documents.get(URI).tree);
		let diags = unknownImportSymbols(URI, documents.get(URI));
		assert.match(1, length(diags));
		assert.match(contains("'default'"), diags[0].message);
		assert.match({ start: src.at[0], end: src.at[1] }, diags[0].range);
	});
});
