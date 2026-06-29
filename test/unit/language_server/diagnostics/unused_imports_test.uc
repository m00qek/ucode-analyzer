import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { unusedImports } from 'language_server.diagnostics.unused_imports';

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
		let diags = unusedImports(open("import { foo } from 'tree_sitter';\n"));
		assert.match(1, length(diags));
		assert.match(4, diags[0].severity);   // HINT
		assert.match('unused-import', diags[0].code);
		assert.match(true, index(diags[0].message, "'foo'") >= 0);
	});

	it('does not hint for a named import that is used', () => {
		let diags = unusedImports(open("import { parse } from 'tree_sitter';\nparse('x');\n"));
		assert.match(0, length(diags));
	});

	it('hints for a namespace alias that is never referenced', () => {
		let diags = unusedImports(open("import * as ts from 'tree_sitter';\n"));
		assert.match(1, length(diags));
		assert.match('unused-import', diags[0].code);
		assert.match(true, index(diags[0].message, "'ts'") >= 0);
	});

	it('does not hint for a namespace alias that is used', () => {
		let diags = unusedImports(open("import * as ts from 'tree_sitter';\nts.parse;\n"));
		assert.match(0, length(diags));
	});

	it('handles aliased imports: uses local name, not original', () => {
		// import { foo as bar } — bar is the local name; using bar is fine
		let used   = unusedImports(open("import { foo as bar } from 'tree_sitter';\nbar();\n"));
		let unused = unusedImports(open("import { foo as bar } from 'tree_sitter';\n"));
		assert.match(0, length(used));
		assert.match(1, length(unused));
		assert.match(true, index(unused[0].message, "'bar'") >= 0);
	});

	it('reports each unused specifier individually', () => {
		let diags = unusedImports(open("import { a, b, c } from 'tree_sitter';\n"));
		assert.match(3, length(diags));
	});

	it('does not report specifiers used in the same import block', () => {
		// 'a' used, 'b' not — only 'b' warned
		let diags = unusedImports(open("import { a, b } from 'tree_sitter';\na();\n"));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'b'") >= 0);
	});

	it('range points at the local identifier token', () => {
		let diags = unusedImports(open("import { foo } from 'tree_sitter';\n"));
		let r = diags[0].range;
		// 'foo' starts at col 9 on line 0
		assert.match(0, r.start.line);
		assert.match(9, r.start.character);
		assert.match(0, r.end.line);
		assert.match(12, r.end.character);
	});
});
