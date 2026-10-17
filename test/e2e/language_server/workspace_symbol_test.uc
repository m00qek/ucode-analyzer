import { describe, it, assert, setup, teardown } from 'utest';
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

// The symbols of t.uc among the results.
function inT(symbols) {
	return filter(symbols, (s) => s.location.uri === 'file:///t.uc');
}

// t.uc's symbol `name` of this SymbolKind, from marker a to marker b of src.
function symbol(src, name, kind, a, b) {
	return {
		name, kind, containerName: 't.uc',
		location: { uri: 'file:///t.uc', range: { start: src.at[a], end: src.at[b] } },
	};
}

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
		let src = cursors("export function $1greet$2() {};\nexport let $3count$4 = 0;\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: '' } });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		// The fixture workspace exports a greet of its own: count only t.uc's.
		assert.match([
			symbol(src, 'greet', 12, 1, 2),   // Function
			symbol(src, 'count', 13, 3, 4),   // Variable
		], inT(resp.result));
	});

	it('substring query filters results', () => {
		let src = cursors("export function $1handleRequest$2() {};\nexport function init() {};\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: 'req' } });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		// Declarations elsewhere match 'req' too (require, ...): count only t.uc's.
		assert.match([ symbol(src, 'handleRequest', 12, 1, 2) ], inT(resp.result));
	});

	it('result includes location with uri and range', () => {
		let src = cursors("export function $1handleConn$2() {};\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: 'handleConn' } });
		let resp = lsp.receive(proc);

		assert.match([ symbol(src, 'handleConn', 12, 1, 2) ], resp.result);
	});

	it('non-exported symbols are not returned', () => {
		let src = cursors("function hidden() {}\nexport function $1visible$2() {};\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'workspace/symbol', params: { query: '' } });
		let resp = lsp.receive(proc);

		assert.match([ symbol(src, 'visible', 12, 1, 2) ], inT(resp.result));
	});
});
