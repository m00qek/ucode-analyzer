import { describe, it, assert, setup, teardown, contains, not } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('workspace/symbol', () => {

	it('capability is advertised in initialize response', () => {
		// initialize is called in beforeEach; the response was already received.
		// Re-initialize in a fresh session so we can capture the response.
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.workspaceSymbolProvider === true);
	});

	it('empty query returns exported symbols from indexed files', () => {
		lsp.open(proc, 'file:///t.uc', "export function greet() {};\nexport let count = 0;\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: '' } });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, type(resp.result) === 'array');
		// The fixture workspace exports a greet of its own: count only t.uc's.
		let names = map(filter(resp.result, (s) => s.location.uri === 'file:///t.uc'), (s) => s.name);
		assert.match(contains(['greet']), names);
		assert.match(contains(['count']), names);
	});

	it('substring query filters results', () => {
		lsp.open(proc, 'file:///t.uc', "export function handleRequest() {};\nexport function init() {};\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: 'req' } });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		let names = map(resp.result, (s) => s.name);
		assert.match(contains(['handleRequest']), names);
		assert.match(not(contains(['init'])), names);
	});

	it('result includes location with uri and range', () => {
		let src = cursors("export function $1handleConn$2() {};\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: 'handleConn' } });
		let resp = lsp.receive(proc);

		let s = filter(resp.result, (s) => s.name === 'handleConn' && s.location.uri === 'file:///t.uc')[0];
		assert.match(true, s !== null);
		assert.match('file:///t.uc', s.location.uri);
		assert.match({ start: src.at[1], end: src.at[2] }, s.location.range);
	});

	it('non-exported symbols are not returned', () => {
		lsp.open(proc, 'file:///t.uc', "function hidden() {}\nexport function visible() {};\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: '' } });
		let resp = lsp.receive(proc);

		let names = map(resp.result, (s) => s.name);
		assert.match(not(contains(['hidden'])), names);
		assert.match(contains(['visible']), names);
	});
});
