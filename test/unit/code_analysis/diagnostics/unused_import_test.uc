import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unusedImports } from 'ucode_analyzer.code_analysis.diagnostics.unused_import';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The hints for a marked snippet: one per unused local name, on the marker
// pairs ($0,$1), ($2,$3), … in order.
function check(marked, ...names) {
	let src = cursors(marked), want = [];
	for (let i = 0; i < length(names); i++)
		push(want, {
			range: { start: src.at[2 * i], end: src.at[2 * i + 1] }, severity: 4, source: 'ucode-analyzer',
			code: 'unused-import', message: sprintf("'%s' is imported but never used", names[i]),
		});
	return { want, got: unusedImports(open(src.text)) };
}

describe('diagnostics — unused imports', () => {
	it('returns empty list when there are no imports', () => {
		assert.match(0, length(unusedImports(open("let x = 1;\n"))));
	});

	it('hints for a named import that is never referenced, on its identifier', () => {
		let r = check("import { $0foo$1 } from 'parser';\n", 'foo');
		assert.match(r.want, r.got);  // a HINT
	});

	it('does not hint for a named import that is used', () => {
		let diags = unusedImports(open("import { parse } from 'parser';\nparse('x');\n"));
		assert.match(0, length(diags));
	});

	it('hints for a namespace alias that is never referenced', () => {
		let r = check("import * as $0ts$1 from 'parser';\n", 'ts');
		assert.match(r.want, r.got);
	});

	it('does not hint for a namespace alias that is used', () => {
		let diags = unusedImports(open("import * as ts from 'parser';\nts.parse;\n"));
		assert.match(0, length(diags));
	});

	it('handles aliased imports: uses local name, not original', () => {
		// import { foo as bar } — bar is the local name; using bar is fine
		let used = unusedImports(open("import { foo as bar } from 'parser';\nbar();\n"));
		assert.match(0, length(used));
		let r = check("import { foo as $0bar$1 } from 'parser';\n", 'bar');
		assert.match(r.want, r.got);
	});

	it('reports each unused specifier individually', () => {
		let r = check("import { $0a$1, $2b$3, $4c$5 } from 'parser';\n", 'a', 'b', 'c');
		assert.match(r.want, r.got);
	});

	it('does not report specifiers used in the same import block', () => {
		// 'a' used, 'b' not — only 'b' warned
		let r = check("import { a, $0b$1 } from 'parser';\na();\n", 'b');
		assert.match(r.want, r.got);
	});
});
