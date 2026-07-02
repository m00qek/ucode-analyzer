import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import * as dag from 'code_analysis.dag.dag';
import { workspaceSymbol } from 'language_server.handlers.workspace_symbol';

let URI_A = 'file:///a.uc';
let URI_B = 'file:///b.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

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

	it('location range end is offset by name length from start', () => {
		addDoc(URI_A, "export function greet() {};\n");
		let syms = workspaceSymbol('');
		let s = filter(syms, (s) => s.name === 'greet')[0];
		let r = s.location.range;
		assert.match(r.start.line, r.end.line);
		assert.match(r.start.character + length('greet'), r.end.character);
	});

	it('empty query returns all exported symbols', () => {
		addDoc(URI_A, "export function a() {};\nexport function b() {};\n");
		let names = map(workspaceSymbol(''), (s) => s.name);
		assert.match(true, index(names, 'a') >= 0);
		assert.match(true, index(names, 'b') >= 0);
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
		assert.match(true, index(names, 'fromA') >= 0);
		assert.match(true, index(names, 'fromB') >= 0);
	});

	it('non-exported declarations are not included', () => {
		addDoc(URI_A, "function hidden() {}\nexport function visible() {};\n");
		let names = map(workspaceSymbol(''), (s) => s.name);
		assert.match(false, index(names, 'hidden') >= 0);
		assert.match(true, index(names, 'visible') >= 0);
	});

	it('query with no matches returns empty list', () => {
		addDoc(URI_A, "export function greet() {};\n");
		assert.match(0, length(workspaceSymbol('zzznomatch')));
	});
});
