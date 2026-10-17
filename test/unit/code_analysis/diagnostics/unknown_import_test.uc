import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unknownImports } from 'ucode_analyzer.code_analysis.diagnostics.unknown_import';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

let _config = fixture.config();

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
});

// The errors for a marked snippet: one per unresolved module, on the marker
// pairs ($0,$1), ($2,$3), … around its quoted specifier.
function check(marked) {
	let src = cursors(marked), want = [];
	for (let i = 0; i + 1 < length(src.at); i += 2) {
		let spec = substr(src.text, src.offset[i] + 1, src.offset[i + 1] - src.offset[i] - 2);
		push(want, {
			range: { start: src.at[i], end: src.at[i + 1] }, severity: 1, source: 'ucode-analyzer',
			code: 'unknown-import', message: sprintf("Cannot find module '%s'", spec),
		});
	}
	documents.open(URI, src.text, 1);
	dag.add(URI, src.text, documents.get(URI).tree);
	return { want, got: unknownImports(URI, documents.get(URI)) };
}

describe('diagnostics — unknown imports', () => {
	it('returns empty list for a valid import', () => {
		let text = "import * as ts from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImports(URI, documents.get(URI))));
	});

	it('errors on an import that cannot be resolved, on the module string only', () => {
		let r = check("import { foo } from $0'no_such_module'$1;\n");
		assert.match("Cannot find module 'no_such_module'", r.want[0].message);
		assert.match(r.want, r.got);
	});

	it('reports one error per unresolved import', () => {
		let r = check("import { a } from $0'bad_a'$1;\nimport { b } from $2'bad_b'$3;\n");
		assert.match(r.want, r.got);
	});

	it('reports only one diagnostic when the same bad module is imported twice', () => {
		let r = check("import { a } from $0'bad_mod'$1;\nimport { b } from 'bad_mod';\n");
		assert.match(r.want, r.got);
	});

	it('returns empty list when there are no imports', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImports(URI, documents.get(URI))));
	});
});
