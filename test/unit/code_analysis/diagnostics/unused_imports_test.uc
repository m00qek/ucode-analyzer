import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unusedImports } from 'ucode_analyzer.code_analysis.diagnostics.unused_imports';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — unused imports', () => {
	it('returns empty list when there are no imports', () => {
		assert.match(0, length(unusedImports(open("let x = 1;\n"))));
	});

	it('hints for a named import that is never referenced', () => {
		let diags = unusedImports(open("import { foo } from 'parser';\n"));
		assert.match(1, length(diags));
		assert.match(4, diags[0].severity);   // HINT
		assert.match('unused-import', diags[0].code);
		assert.match(contains("'foo'"), diags[0].message);
	});

	it('does not hint for a named import that is used', () => {
		let diags = unusedImports(open("import { parse } from 'parser';\nparse('x');\n"));
		assert.match(0, length(diags));
	});

	it('hints for a namespace alias that is never referenced', () => {
		let diags = unusedImports(open("import * as ts from 'parser';\n"));
		assert.match(1, length(diags));
		assert.match('unused-import', diags[0].code);
		assert.match(contains("'ts'"), diags[0].message);
	});

	it('does not hint for a namespace alias that is used', () => {
		let diags = unusedImports(open("import * as ts from 'parser';\nts.parse;\n"));
		assert.match(0, length(diags));
	});

	it('handles aliased imports: uses local name, not original', () => {
		// import { foo as bar } — bar is the local name; using bar is fine
		let used   = unusedImports(open("import { foo as bar } from 'parser';\nbar();\n"));
		let unused = unusedImports(open("import { foo as bar } from 'parser';\n"));
		assert.match(0, length(used));
		assert.match(1, length(unused));
		assert.match(contains("'bar'"), unused[0].message);
	});

	it('reports each unused specifier individually', () => {
		let diags = unusedImports(open("import { a, b, c } from 'parser';\n"));
		assert.match(3, length(diags));
	});

	it('does not report specifiers used in the same import block', () => {
		// 'a' used, 'b' not — only 'b' warned
		let diags = unusedImports(open("import { a, b } from 'parser';\na();\n"));
		assert.match(1, length(diags));
		assert.match(contains("'b'"), diags[0].message);
	});

	it('range points at the local identifier token', () => {
		let src = cursors("import { $0foo$1 } from 'parser';\n");
		let diags = unusedImports(open(src.text));
		assert.match({ start: src.at[0], end: src.at[1] }, diags[0].range);
	});
});
