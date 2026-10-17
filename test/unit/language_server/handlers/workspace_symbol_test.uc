import { describe, it, assert, beforeEach, afterEach, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { workspaceSymbol } from 'ucode_analyzer.language_server.handlers.workspace_symbol';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI_A = 'file:///a.uc';
let URI_B = 'file:///b.uc';

let _config = fixture.config();

function addDoc(uri, text) {
	documents.open(uri, text, 1);
	dag.add(uri, text, documents.get(uri).tree);
}

// The SymbolInformation of an export in `uri`, spanning marker pair 1–2 of `src`.
function symbol(name, kind, uri, src) {
	return {
		name, kind,
		location: { uri, range: { start: src.at[1], end: src.at[2] } },
		containerName: replace(uri, /^.*\//, ''),
	};
}

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI_A);
	documents.close(URI_B);
	dag.remove(URI_A);
	dag.remove(URI_B);
});

describe('workspace/symbol', () => {
	it('returns empty list when no files are indexed', () => {
		assert.match([], workspaceSymbol(''));
	});

	it('returns exported function with FUNCTION kind (12)', () => {
		let src = cursors("export function $1greet$2() {};\n");
		addDoc(URI_A, src.text);
		assert.match([ symbol('greet', 12, URI_A, src) ], workspaceSymbol(''));
	});

	it('returns exported variable with VARIABLE kind (13)', () => {
		let src = cursors("export let $1count$2 = 0;\n");
		addDoc(URI_A, src.text);
		assert.match([ symbol('count', 13, URI_A, src) ], workspaceSymbol(''));
	});

	it('includes location with uri', () => {
		addDoc(URI_A, "export function greet() {};\n");
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'greet')[0];
		assert.match(URI_A, s.location.uri);
	});

	it('includes containerName derived from URI basename', () => {
		addDoc(URI_A, "export function greet() {};\n");
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'greet')[0];
		assert.match('a.uc', s.containerName);
	});

	it('location range spans the name', () => {
		let src = cursors("export function $1greet$2() {};\n");
		addDoc(URI_A, src.text);
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'greet')[0];
		assert.match({ start: src.at[1], end: src.at[2] }, s.location.range);
	});

	it('empty query returns all exported symbols', () => {
		addDoc(URI_A, "export function a() {};\nexport function b() {};\n");
		let names = map(workspaceSymbol(''), (s) => s.name);
		assert.match(any_order([ 'a', 'b' ]), names);
	});

	it('filters by case-insensitive substring match', () => {
		let src = cursors("export function $1handleRequest$2() {};\nexport function init() {};\n");
		addDoc(URI_A, src.text);
		assert.match([ symbol('handleRequest', 12, URI_A, src) ], workspaceSymbol('req'));
	});

	it('query is case-insensitive', () => {
		let src = cursors("export function $1handleRequest$2() {};\n");
		addDoc(URI_A, src.text);
		assert.match([ symbol('handleRequest', 12, URI_A, src) ], workspaceSymbol('REQ'));
	});

	it('returns symbols from multiple files', () => {
		let srcA = cursors("export function $1fromA$2() {};\n");
		let srcB = cursors("export function $1fromB$2() {};\n");
		addDoc(URI_A, srcA.text);
		addDoc(URI_B, srcB.text);
		assert.match(any_order([ symbol('fromA', 12, URI_A, srcA), symbol('fromB', 12, URI_B, srcB) ]), workspaceSymbol(''));
	});

	it('non-exported declarations are not included', () => {
		addDoc(URI_A, "function hidden() {}\nexport function visible() {};\n");
		assert.match([ 'visible' ], map(workspaceSymbol(''), (s) => s.name));
	});

	it('query with no matches returns empty list', () => {
		addDoc(URI_A, "export function greet() {};\n");
		assert.match([], workspaceSymbol('zzznomatch'));
	});
});
