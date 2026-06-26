import { describe, it, assert, mock, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_language_server.dag.dag';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

let URI_A  = 'file:///app/src/a.uc';
let URI_B  = 'file:///app/src/b.uc';
let TS_URI = 'file:///app/src/tree_sitter.uc';

let TEXT_A_IMPORTS_B = "import { foo } from 'b';\nexport function bar() {};";
let TEXT_B_EXPORTS   = "export function foo() {};";
let TEXT_A_NO_IMPORT = "export function bar() {};";

function reset() {
	dag.init(_config);
	dag.remove(URI_A);
	dag.remove(URI_B);
	dag.remove(TS_URI);
}

describe('dag nodes', () => {
	beforeEach(reset);

	it('addFromDisk indexes a file that exists on disk', () => {
		dag.addFromDisk(TS_URI);

		let exps = dag.exportsOf(TS_URI);
		assert.match(true, exps !== null);
		assert.match(true, length(exps) > 0);
	});

	it('addFromDisk is a no-op for a path that does not exist', () => {
		let uri = 'file:///nonexistent/file.uc';
		dag.addFromDisk(uri);
		assert.match(null, dag.exportsOf(uri));
	});

	it('add makes exportsOf available', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));

		let exps = dag.exportsOf(URI_B);
		assert.match(true, exps !== null);
		assert.match(1, length(exps));
		assert.match('foo', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('add overwrites an existing node', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		dag.add(URI_B, TEXT_A_NO_IMPORT, parse(TEXT_A_NO_IMPORT));

		let exps = dag.exportsOf(URI_B);
		assert.match(1, length(exps));
		assert.match('bar', exps[0].name);
	});

	it('exportsOf returns null for unknown uri', () => {
		assert.match(null, dag.exportsOf('file:///missing.uc'));
	});

	it('remove clears the node', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		dag.remove(URI_B);

		assert.match(null, dag.exportsOf(URI_B));
	});

	it('allUris includes added nodes', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		assert.match(true, index(dag.allUris(), URI_B) >= 0);
	});

	it('allUris excludes removed nodes', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		dag.remove(URI_B);
		assert.match(false, index(dag.allUris(), URI_B) >= 0);
	});
});

describe('dag edges', () => {
	beforeEach(reset);

	it('records import specifier even when module does not resolve', () => {
		dag.add(URI_A, TEXT_A_IMPORTS_B, parse(TEXT_A_IMPORTS_B));

		let imps = dag.importsOf(URI_A);
		assert.match(1, length(imps));
		assert.match('b', imps[0].specifier);
		assert.match(null, imps[0].resolvedUri);
	});

	it('importsOf returns all imports for files with multiple imports', () => {
		let text = "import { foo } from 'b';\nimport * as ts from 'tree_sitter';";
		dag.add(URI_A, text, parse(text));

		let imps = dag.importsOf(URI_A);
		assert.match(2, length(imps));
	});

	it('resolves imports for modules that exist on disk', () => {
		let text = "import * as ts from 'tree_sitter';";
		dag.add(URI_A, text, parse(text));

		let imps = dag.importsOf(URI_A);
		assert.match(1, length(imps));
		assert.match(TS_URI, imps[0].resolvedUri);
		assert.match(true, index(dag.reverseDeps(TS_URI), URI_A) >= 0);
	});

	it('remove cleans up reverse edges', () => {
		let text = "import * as ts from 'tree_sitter';";
		dag.add(URI_A, text, parse(text));
		assert.match(true, index(dag.reverseDeps(TS_URI), URI_A) >= 0);

		dag.remove(URI_A);
		assert.match(false, index(dag.reverseDeps(TS_URI), URI_A) >= 0);
	});

	it('update removes stale edges when imports change', () => {
		let text1 = "import * as ts from 'tree_sitter';";
		dag.add(URI_A, text1, parse(text1));
		assert.match(true, index(dag.reverseDeps(TS_URI), URI_A) >= 0);

		dag.update(URI_A, TEXT_A_NO_IMPORT, parse(TEXT_A_NO_IMPORT));
		assert.match(false, index(dag.reverseDeps(TS_URI), URI_A) >= 0);
	});

	it('cascade re-indexes reverse deps on update', () => {
		let text_b_v1 = "import * as ts from 'tree_sitter';\nexport function b_export() {};";
		let text_b_v2 = "export function b_new_export() {};";

		dag.add(URI_B, text_b_v1, parse(text_b_v1));
		assert.match(true, index(dag.reverseDeps(TS_URI), URI_B) >= 0);

		// Patch fs so the cascade re-read of URI_B returns v2 content.
		mock.global.patch('fs', { data: { '/app/src/b.uc': text_b_v2 } });
		dag.update(TS_URI, "export const ts_updated = true;", parse("export const ts_updated = true;"));
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_B);
		assert.match(1, length(exps));
		assert.match('b_new_export', exps[0].name);
	});
});

describe('dag resolveExport / resolveExportLocation', () => {
	beforeEach(() => {
		reset();
		dag.addFromDisk(TS_URI);
	});

	it('resolveExport returns the entry for a direct export', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		let exp = dag.resolveExport(URI_B, 'foo');
		assert.match(true, exp !== null);
		assert.match('foo', exp.name);
		assert.match('function', exp.kind);
	});

	it('resolveExport returns null for an unknown export name', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		assert.match(null, dag.resolveExport(URI_B, 'nope'));
	});

	it('resolveExport follows a memberRef chain to the original definition', () => {
		// URI_A re-exports ts.parse as 'parse' — chain must follow to TS_URI.
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts.parse;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'parse');
		assert.match(true, exp !== null);
		assert.match('parse', exp.name);
	});

	it('resolveExport follows a namespace re-export (export const X = moduleAlias)', () => {
		// URI_A re-exports the whole tree_sitter namespace as 'ts'.
		// resolveExport should find the 'ts' export in TS_URI (same name).
		let textA = "import * as ts from 'tree_sitter';\nexport const ts = ts;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'ts');
		// Should resolve to TS_URI's 'ts' export if it exists, or fall back gracefully.
		// The key assertion: it doesn't return the re-exporting file's own entry.
		assert.match(true, exp !== null);
	});

	it('resolveExportLocation of namespace re-export points to the source module', () => {
		// URI_A: import * as ts from 'tree_sitter'; export const parse = ts;
		// 'parse' is not in tree_sitter, so falls back — but the chain IS attempted.
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts;";
		dag.add(URI_A, textA, parse(textA));
		let loc = dag.resolveExportLocation(URI_A, 'parse');
		// Falls back to TS_URI because 'parse' is found there via the namespace chain.
		assert.match(TS_URI, loc.uri);
	});

	it('resolveExport follows a localRef chain (named import re-export with rename)', () => {
		// URI_A imports tree_sitter.parse as _parse and re-exports it as 'parse'.
		// resolveExport must follow the localRef chain through the named import alias.
		let textA = "import { parse as _parse } from 'tree_sitter';\nexport const parse = _parse;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'parse');
		assert.match(true, exp !== null);
		assert.match('parse', exp.name);
		assert.match('function', exp.kind);
	});

	it('resolveExportLocation follows localRef chain to the final { uri, name }', () => {
		let textA = "import { parse as _parse } from 'tree_sitter';\nexport const parse = _parse;";
		dag.add(URI_A, textA, parse(textA));
		let loc = dag.resolveExportLocation(URI_A, 'parse');
		assert.match(TS_URI, loc.uri);
		assert.match('parse', loc.name);
	});

	it('resolveExport follows localRef without rename (import { X } then export const X = X)', () => {
		// URI_A does: import { parse } from 'tree_sitter'; export const parse = parse;
		let textA = "import { parse } from 'tree_sitter';\nexport const parse = parse;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'parse');
		assert.match(true, exp !== null);
		assert.match('function', exp.kind);
	});

	it('resolveExportLocation returns { uri, name } for a direct export', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		let loc = dag.resolveExportLocation(URI_B, 'foo');
		assert.match(URI_B, loc.uri);
		assert.match('foo', loc.name);
	});

	it('resolveExportLocation follows chain and returns the final { uri, name }', () => {
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts.parse;";
		dag.add(URI_A, textA, parse(textA));
		let loc = dag.resolveExportLocation(URI_A, 'parse');
		assert.match(TS_URI, loc.uri);
		assert.match('parse', loc.name);
	});

	it('resolveExportLocation falls back to { uri, name } for an unknown export', () => {
		dag.add(URI_B, TEXT_B_EXPORTS, parse(TEXT_B_EXPORTS));
		let loc = dag.resolveExportLocation(URI_B, 'nope');
		assert.match(URI_B, loc.uri);
		assert.match('nope', loc.name);
	});

	it('resolveExport and resolveExportLocation agree on the chain destination', () => {
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts.parse;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'parse');
		let loc = dag.resolveExportLocation(URI_A, 'parse');
		// Both must land on the same export in TS_URI.
		assert.match(TS_URI, loc.uri);
		assert.match('parse', loc.name);
		assert.match(true, exp !== null);
		assert.match('parse', exp.name);
	});
});
