import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unknownImportSymbols } from 'ucode_analyzer.code_analysis.diagnostics.unknown_import_symbol';
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

// The errors for a marked snippet: one per missing export, named in order by
// `names`, on the marker pairs ($0,$1), ($2,$3), ….
function check(marked, ...names) {
	let src = cursors(marked), want = [];
	for (let i = 0; i < length(names); i++)
		push(want, {
			range: { start: src.at[2 * i], end: src.at[2 * i + 1] }, severity: 1, source: 'ucode-analyzer',
			code: 'unknown-import-symbol', message: sprintf("Module has no export named '%s'", names[i]),
		});
	documents.open(URI, src.text, 1);
	dag.add(URI, src.text, documents.get(URI).tree);
	return { want, got: unknownImportSymbols(URI, documents.get(URI)) };
}

describe('diagnostics — unknown import symbols', () => {
	it('returns empty list when all named imports exist in the module', () => {
		let text = "import { parse } from 'parser';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(0, length(unknownImportSymbols(URI, documents.get(URI))));
	});

	it('errors on a named import that is not exported, on the remote name only', () => {
		let r = check("import { $0noSuchExport$1 } from 'parser';\n", 'noSuchExport');
		assert.match(r.want, r.got);
	});

	it('reports one error per bad symbol when multiple are wrong', () => {
		let r = check("import { $0bad1$1, $2bad2$3 } from 'parser';\n", 'bad1', 'bad2');
		assert.match(r.want, r.got);
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
		let r = check("import { $0noSuch$1 as local } from 'parser';\n", 'noSuch');
		assert.match(r.want, r.got);
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
		let r = check("import $0x$1 from 'parser';\n", 'default');
		assert.match(r.want, r.got);
	});
});
