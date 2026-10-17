import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unknownImports } from 'ucode_analyzer.code_analysis.diagnostics.unknown_imports';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';

let URI = 'file:///test.uc';

let _config = {
	workspaceDir: '/app',
	selfSrcDir: '/app/src/ucode_analyzer',
	workspace: { libraryPaths: ['src'] },
};

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
});

describe('diagnostics — unknown imports', () => {
	it('returns empty list for a valid import', () => {
		let text = "import * as ts from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImports(URI, documents.get(URI))));
	});

	it('returns an error for an import that cannot be resolved', () => {
		let text = "import { foo } from 'no_such_module';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let diags = unknownImports(URI, documents.get(URI));

		assert.match(1, length(diags));
		assert.match(1, diags[0].severity);
		assert.match(true, index(diags[0].message, 'no_such_module') >= 0);
	});

	it('highlights the module string node, not the whole statement', () => {
		let text = "import { foo } from 'no_such_module';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let r = unknownImports(URI, documents.get(URI))[0].range;

		assert.match(0, r.start.line);
		assert.match(true, r.start.character >= 20);
	});

	it('reports one error per unresolved import', () => {
		let text = "import { a } from 'bad_a';\nimport { b } from 'bad_b';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(2, length(unknownImports(URI, documents.get(URI))));
	});

	it('reports only one diagnostic when the same bad module is imported twice', () => {
		let text = "import { a } from 'bad_mod';\nimport { b } from 'bad_mod';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(1, length(unknownImports(URI, documents.get(URI))));
	});

	it('returns empty list when there are no imports', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImports(URI, documents.get(URI))));
	});
});
