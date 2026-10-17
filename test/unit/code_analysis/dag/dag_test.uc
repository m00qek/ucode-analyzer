import { describe, it, assert, mock, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as mode from 'code_analysis.mode';
import * as dag from 'code_analysis.dag.dag';

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

	it('shorthand property { foo } in exported object is indexed as a property', () => {
		let text = "function foo() {}\nexport const obj = { foo };\n";
		dag.add(URI_B, text, parse(text));

		let exps = dag.exportsOf(URI_B);
		assert.match(1, length(exps));
		assert.match('obj', exps[0].name);
		assert.match(true, exps[0].properties !== null);
		assert.match(1, length(exps[0].properties));
		assert.match('foo', exps[0].properties[0].name);
		assert.match('function', exps[0].properties[0].kind);
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

	it('does not cascade when the interface is unchanged', () => {
		// tree_sitter.uc exists on disk, so the import resolves to it.
		let lib = "/**\n * @returns {string}\n */\nexport function foo() { return 'x'; };\n";
		let importer = "import { foo } from 'tree_sitter';\n";
		dag.add(TS_URI, lib, parse(lib));
		dag.add(URI_A, importer, parse(importer));
		dag.markOpen(URI_A);
		let open = { [URI_A]: { text: importer, tree: parse(importer) } };

		let body = "/**\n * @returns {string}\n */\nexport function foo() { let s = 'y'; return s; };\n";
		assert.match([], dag.update(TS_URI, body, parse(body), open));
		// Positions move with an edit above the export; importers do not keep them.
		let moved = "// a comment\n\n" + body;
		assert.match([], dag.update(TS_URI, moved, parse(moved), open));
		assert.match(5, dag.exportsOf(TS_URI)[0].position.line);

		let retyped = "/**\n * @returns {int}\n */\nexport function foo() { return 1; };\n";
		assert.match([URI_A], dag.update(TS_URI, retyped, parse(retyped), open));
		dag.markClosed(URI_A);
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

	it('resolveExport follows a namespace re-export to a same-named export in the source module', () => {
		// URI_A: import * as ts from 'tree_sitter'; export const parse = ts;
		// 'parse' exists in tree_sitter — the chain must find it there.
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'parse');
		assert.match(true, exp !== null);
		assert.match('parse', exp.name);
		assert.match('function', exp.kind);
	});

	it('resolveExportLocation of namespace re-export points to the source module', () => {
		let textA = "import * as ts from 'tree_sitter';\nexport const parse = ts;";
		dag.add(URI_A, textA, parse(textA));
		let loc = dag.resolveExportLocation(URI_A, 'parse');
		assert.match(TS_URI, loc.uri);
	});

	it('resolveExport of namespace re-export synthesises module type when source is not indexed', () => {
		// URI_A: import * as ts from 'unknown_module'; export const ns = ts;
		// 'unknown_module' is not on disk — resolvedUri is null.
		// Must not return null; must return a synthetic exp with _moduleSpecifier.
		let textA = "import * as ts from 'unknown_module';\nexport const ns = ts;";
		dag.add(URI_A, textA, parse(textA));
		let exp = dag.resolveExport(URI_A, 'ns');
		assert.match(true, exp !== null);
		assert.match('unknown_module', exp._moduleSpecifier);
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

describe('dag.resolveMember', () => {
	beforeEach(reset);

	it('returns { exp, uri, name } for an existing export', () => {
		let r = dag.resolveMember('tree_sitter', 'parse');
		assert.match(true, r !== null);
		assert.match(TS_URI, r.uri);
		assert.match('parse', r.name);
		assert.match('function', r.exp.kind);
	});

	it('returns null for an unknown specifier', () => {
		assert.match(null, dag.resolveMember('does.not.exist', 'foo'));
	});

	it('returns null for a specifier that resolves but has no such export', () => {
		assert.match(null, dag.resolveMember('tree_sitter', 'doesNotExist'));
	});

	it('lazy-indexes the module on first access', () => {
		// tree_sitter is not yet in the DAG after reset
		assert.match(null, dag.exportsOf(TS_URI));
		let r = dag.resolveMember('tree_sitter', 'parse');
		assert.match(true, r !== null);
		// Now the module is indexed as a side-effect
		assert.match(true, dag.exportsOf(TS_URI) !== null);
	});
});

describe('dag cascade pruning of deleted files', () => {
	beforeEach(reset);

	it('removes a cascade dep that no longer exists on disk', () => {
		// URI_B imports tree_sitter. After TS is updated, the cascade tries to re-index B.
		// If B's file has been deleted (readAndParse returns null), B must be pruned.
		let text_b = "import * as ts from 'tree_sitter';\nexport function bFn() {};";
		dag.addFromDisk(TS_URI);
		dag.add(URI_B, text_b, parse(text_b));
		assert.match(true, dag.exportsOf(URI_B) !== null);

		// Mock fs so b.uc is "missing" (open returns null).
		mock.global.patch('fs', { data: {} });
		dag.update(TS_URI, "export const updated = true;", parse("export const updated = true;"));
		mock.global.unpatch('fs');

		assert.match(null, dag.exportsOf(URI_B));
	});

	it('cascades through a deleted dep to its own reverse deps', () => {
		// Chain: TS_URI ← URI_B ← URI_A.
		// When TS is updated, cascade visits B (deleted) then A (re-indexed).
		let text_b = "import * as ts from 'tree_sitter';\nexport function bFn() {};";
		let text_a_v1 = "import { bFn } from 'b';\nexport function aFn() {};";
		let text_a_v2 = "import { bFn } from 'b';\nexport function aNewFn() {};";

		dag.addFromDisk(TS_URI);
		dag.add(URI_B, text_b, parse(text_b));
		// URI_A imports 'b' — patch fs so resolveModule finds b.uc on disk and creates the edge.
		mock.global.patch('fs', { data: { '/app/src/b.uc': text_b } });
		dag.add(URI_A, text_a_v1, parse(text_a_v1));
		mock.global.unpatch('fs');

		// Cascade: B is now deleted, A has new content on disk.
		mock.global.patch('fs', { data: { '/app/src/a.uc': text_a_v2 } });
		dag.update(TS_URI, "export const updated = true;", parse("export const updated = true;"));
		mock.global.unpatch('fs');

		// B is gone.
		assert.match(null, dag.exportsOf(URI_B));
		// A was re-indexed from disk with v2 exports.
		let exps = dag.exportsOf(URI_A);
		let names = map(exps ?? [], (e) => e.name);
		assert.match(true, index(names, 'aNewFn') >= 0);
	});
});

describe('dag cascade skips unchanged on-disk dependents', () => {
	beforeEach(reset);

	let B_TEXT   = "export function foo() {};";
	let B_TEXT_2 = "export const foo = 1;";
	// A imports 'b', so an update to b.uc cascades to a.uc. v1/v2 are the same
	// byte length (export name aa/bb) so the mock's stat reports an identical
	// (mtime:0, size) stamp — the cascade must skip re-reading a.uc.
	let A_V1 = "import { foo } from 'b';\nexport function aa() {};";
	let A_V2 = "import { foo } from 'b';\nexport function bb() {};";
	// Longer name → different size → stamp mismatch → cascade must re-read.
	let A_V2_LONGER = "import { foo } from 'b';\nexport function aaLong() {};";

	it('does not re-index a dependent whose disk stamp is unchanged', () => {
		mock.global.patch('fs', { data: { '/app/src/a.uc': A_V1, '/app/src/b.uc': B_TEXT } });
		dag.addFromDisk(URI_B);
		dag.addFromDisk(URI_A);          // stamps A at size(A_V1)
		mock.global.unpatch('fs');

		// a.uc's on-disk content changed to A_V2 but with the SAME size (and mtime 0),
		// so the stamp still matches. The cascade must skip it and keep A_V1's export.
		mock.global.patch('fs', { data: { '/app/src/a.uc': A_V2, '/app/src/b.uc': B_TEXT } });
		dag.update(URI_B, B_TEXT_2, parse(B_TEXT_2));
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_A);
		assert.match(1, length(exps));
		assert.match('aa', exps[0].name);   // stale-but-skipped, not re-read to 'bb'
	});

	it('re-indexes a dependent whose disk stamp changed (different size)', () => {
		mock.global.patch('fs', { data: { '/app/src/a.uc': A_V1, '/app/src/b.uc': B_TEXT } });
		dag.addFromDisk(URI_B);
		dag.addFromDisk(URI_A);          // stamps A at size(A_V1)
		mock.global.unpatch('fs');

		mock.global.patch('fs', { data: { '/app/src/a.uc': A_V2_LONGER, '/app/src/b.uc': B_TEXT } });
		dag.update(URI_B, B_TEXT_2, parse(B_TEXT_2));
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_A);
		assert.match(1, length(exps));
		assert.match('aaLong', exps[0].name);   // stamp mismatch → re-read
	});
});

describe('dag circular re-export guard', () => {
	beforeEach(reset);

	it('resolveExport does not recurse infinitely on a circular re-export', () => {
		// A re-exports from B, B re-exports from A — without a visited guard this
		// would infinite-loop; with it we must return null cleanly.
		let URI_C = 'file:///app/src/c.uc';
		let textA = "import { bFoo } from 'b';\nexport const aFoo = bFoo;";
		let textB = "import { aFoo } from 'a';\nexport const bFoo = aFoo;";

		dag.init({ workspaceDir: '/app', workspace: { libraryPaths: ['src'] } });
		dag.add(URI_A, textA, parse(textA));
		dag.add(URI_B, textB, parse(textB));
		dag.remove(URI_C);

		// Must return without hanging; result is null or a valid entry.
		let result = dag.resolveExport(URI_A, 'aFoo');
		// The important assertion is that we reached here at all (no infinite loop).
		assert.match(true, result === null || result.name === 'aFoo');
	});
});

describe('dag markOpen / cascade skip', () => {
	// URI_B imports tree_sitter (which exists on disk), so B is a reverse dep of TS_URI.
	// When TS_URI is updated, the cascade would normally re-index B from disk.
	let TEXT_B_IMPORTS_TS_OPEN = "import * as ts from 'tree_sitter';\nexport function openVersion() {};";
	let TEXT_B_IMPORTS_TS_DISK = "import * as ts from 'tree_sitter';\nexport function diskVersion() {};";
	let TEXT_TS_UPDATED = "export const ts_updated = true;";

	beforeEach(() => {
		reset();
		dag.addFromDisk(TS_URI);
		dag.add(URI_B, TEXT_B_IMPORTS_TS_OPEN, parse(TEXT_B_IMPORTS_TS_OPEN));
	});

	it('cascade update does not overwrite an open file from disk', () => {
		dag.markOpen(URI_B);

		mock.global.patch('fs', { data: { '/app/src/b.uc': TEXT_B_IMPORTS_TS_DISK } });
		dag.update(TS_URI, TEXT_TS_UPDATED, parse(TEXT_TS_UPDATED));
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_B);
		let names = map(exps ?? [], (e) => e.name);
		assert.match(true, index(names, 'openVersion') >= 0);
		assert.match(false, index(names, 'diskVersion') >= 0);
	});

	it('cascade re-indexes open file from openDocs memory when provided', () => {
		let TEXT_B_V2 = "import * as ts from 'tree_sitter';\nexport function memoryVersion() {};";
		dag.markOpen(URI_B);

		// Disk has a different version; openDocs has the in-memory content.
		mock.global.patch('fs', { data: { '/app/src/b.uc': TEXT_B_IMPORTS_TS_DISK } });
		dag.update(TS_URI, TEXT_TS_UPDATED, parse(TEXT_TS_UPDATED),
		           { [URI_B]: { text: TEXT_B_V2, tree: parse(TEXT_B_V2) } });
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_B);
		let names = map(exps ?? [], (e) => e.name);
		assert.match(true, index(names, 'memoryVersion') >= 0);
		assert.match(false, index(names, 'diskVersion') >= 0);
		assert.match(false, index(names, 'openVersion') >= 0);
	});

	it('markClosed allows cascade to re-index from disk again', () => {
		dag.markOpen(URI_B);
		dag.markClosed(URI_B);

		mock.global.patch('fs', { data: { '/app/src/b.uc': TEXT_B_IMPORTS_TS_DISK } });
		dag.update(TS_URI, TEXT_TS_UPDATED, parse(TEXT_TS_UPDATED));
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_B);
		let names = map(exps ?? [], (e) => e.name);
		assert.match(true, index(names, 'diskVersion') >= 0);
	});
});

describe('dag — template modules (markup-mode files)', () => {
	beforeEach(reset);

	it('registers exports declared inside template tags', () => {
		let text = "{% export function widget() {}; %}\n<div></div>\n";
		dag.add(URI_B, text, mode.parse(text));

		let exps = dag.exportsOf(URI_B);
		assert.match(1, length(exps));
		assert.match('widget', exps[0].name);
		assert.match('function', exps[0].kind);
	});

	it('resolves an import declared inside a template tag and records the edge', () => {
		let text = "{% import * as ts from 'tree_sitter'; %}\n{{ ts.ucode }}\n";
		dag.add(URI_A, text, mode.parse(text));

		let imps = dag.importsOf(URI_A);
		assert.match(1, length(imps));
		assert.match(TS_URI, imps[0].resolvedUri);
		assert.match(true, index(dag.reverseDeps(TS_URI), URI_A) >= 0);
	});

	it('addFromDisk parses an on-disk template with the markup grammar', () => {
		// dag.uc must route the on-disk read through mode.parse, not a script-only
		// parser — otherwise the template is garbage and yields no exports.
		mock.global.patch('fs', { data: { '/app/src/b.uc': "{% export const TITLE = 'Home'; %}\n<h1></h1>\n" } });
		dag.addFromDisk(URI_B);
		mock.global.unpatch('fs');

		let exps = dag.exportsOf(URI_B);
		assert.match(1, length(exps));
		assert.match('TITLE', exps[0].name);
		assert.match('const', exps[0].kind);
	});
});
