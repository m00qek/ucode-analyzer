import { describe, it, assert, beforeEach, afterEach, contains, not } from 'utest';
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

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI_A);
	documents.close(URI_B);
	dag.remove(URI_A);
	dag.remove(URI_B);
});

describe('workspace/symbol', () => {
	it('returns empty list when no files are indexed', () => {
		assert.match(0, length(workspaceSymbol('')));
	});

	it('returns exported function with FUNCTION kind (12)', () => {
		addDoc(URI_A, "export function greet() {};\n");
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'greet')[0];
		assert.match(true, s !== null);
		assert.match(12, s.kind);
	});

	it('returns exported variable with VARIABLE kind (13)', () => {
		addDoc(URI_A, "export let count = 0;\n");
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'count')[0];
		assert.match(true, s !== null);
		assert.match(13, s.kind);
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
		assert.match(contains(['a']), names);
		assert.match(contains(['b']), names);
	});

	it('filters by case-insensitive substring match', () => {
		addDoc(URI_A, "export function handleRequest() {};\nexport function init() {};\n");
		let syms = workspaceSymbol('req');
		assert.match(1, length(syms));
		assert.match('handleRequest', syms[0].name);
	});

	it('query is case-insensitive', () => {
		addDoc(URI_A, "export function handleRequest() {};\n");
		let syms = workspaceSymbol('REQ');
		assert.match(1, length(syms));
		assert.match('handleRequest', syms[0].name);
	});

	it('returns symbols from multiple files', () => {
		addDoc(URI_A, "export function fromA() {};\n");
		addDoc(URI_B, "export function fromB() {};\n");
		let names = map(workspaceSymbol(''), (s) => s.name);
		assert.match(contains(['fromA']), names);
		assert.match(contains(['fromB']), names);
	});

	it('non-exported declarations are not included', () => {
		addDoc(URI_A, "function hidden() {}\nexport function visible() {};\n");
		let names = map(workspaceSymbol(''), (s) => s.name);
		assert.match(not(contains(['hidden'])), names);
		assert.match(contains(['visible']), names);
	});

	it('query with no matches returns empty list', () => {
		addDoc(URI_A, "export function greet() {};\n");
		assert.match(0, length(workspaceSymbol('zzznomatch')));
	});
});
