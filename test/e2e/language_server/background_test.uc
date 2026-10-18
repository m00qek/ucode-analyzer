import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';
import * as fs from 'fs';

const IMPORTERS = 100;

let proc, ws;

// lib.uc exports helper; each of IMPORTERS files imports it and calls it twice
// from f (line 1), among enough other code that the search outlasts a round trip.
function workspace() {
	let dir = fs.mkdtemp('/tmp/background-XXXXXX');
	fs.writefile(dir + '/lib.uc', 'export function helper(a, b) {\n\treturn a + b;\n}\n');
	let rest = '';
	for (let i = 0; i < 40; i++)
		rest += sprintf("function g%d(a, b) {\n\tlet x = a + b;\n\tif (x > %d) return x;\n\treturn [a, b];\n}\n", i, i);
	for (let i = 0; i < IMPORTERS; i++)
		fs.writefile(sprintf('%s/m%03d.uc', dir, i),
			"import { helper } from 'lib';\nexport function f(x) { return helper(x, 1) + helper(x, 2); }\n" + rest);
	return dir;
}

beforeEach(() => {
	ws = workspace();
	proc = lsp.connect(ws);
	lsp.initialize(proc);
	lsp.open(proc, 'file://' + ws + '/lib.uc', fs.readfile(ws + '/lib.uc'));
});

afterEach(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
	system(['rm', '-rf', ws]);
});

// The cursor on `helper` in lib.uc.
function at() {
	return { textDocument: { uri: 'file://' + ws + '/lib.uc' }, position: { line: 0, character: 17 } };
}

function hover(id) {
	return { jsonrpc: '2.0', id, method: 'textDocument/hover', params: at() };
}

function range(line, from, to) {
	return { start: { line, character: from }, end: { line, character: to } };
}

// The importers' file names, in order.
function importers() {
	let out = [];
	for (let i = 0; i < IMPORTERS; i++) push(out, sprintf('m%03d.uc', i));
	return out;
}

describe('requests over many importers', () => {
	it('finds every reference while answering a hover first', () => {
		lsp.sendAll(proc, [
			{ jsonrpc: '2.0', id: 1, method: 'textDocument/references',
				params: { ...at(), context: { includeDeclaration: true } } },
			hover(2),
		]);
		assert.match(2, lsp.receive(proc).id);
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);

		let want = [ { uri: 'file://' + ws + '/lib.uc', range: range(0, 16, 22) } ];
		for (let f in importers())
			push(want,
				{ uri: 'file://' + ws + '/' + f, range: range(0, 9, 15) },
				{ uri: 'file://' + ws + '/' + f, range: range(1, 30, 36) },
				{ uri: 'file://' + ws + '/' + f, range: range(1, 45, 51) });
		assert.match(want, resp.result);
	});

	it('renames in every importer', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/rename', params: { ...at(), newName: 'h' } });
		let changes = lsp.receive(proc).result.changes;
		assert.match(IMPORTERS + 1, length(changes));
		assert.match([ range(0, 9, 15), range(1, 30, 36), range(1, 45, 51) ],
			map(changes['file://' + ws + '/m042.uc'], (e) => e.range));
	});

	it('finds every incoming call', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 4, method: 'textDocument/prepareCallHierarchy', params: at() });
		let item = lsp.receive(proc).result[0];
		lsp.send(proc, { jsonrpc: '2.0', id: 5, method: 'callHierarchy/incomingCalls', params: { item } });
		let calls = lsp.receive(proc).result;
		assert.match(map(importers(), (f) => 'file://' + ws + '/' + f), map(calls, (c) => c.from.uri));
		assert.match([ 'f' ], uniq(map(calls, (c) => c.from.name)));
		assert.match([ range(1, 30, 36), range(1, 45, 51) ], calls[0].fromRanges);
	});

	it('answers a search cancelled while it runs as cancelled', () => {
		// Once the hover is answered, the search before it is running.
		lsp.sendAll(proc, [
			{ jsonrpc: '2.0', id: 6, method: 'textDocument/references',
				params: { ...at(), context: { includeDeclaration: true } } },
			hover(7),
		]);
		assert.match(7, lsp.receive(proc).id);
		lsp.send(proc, { jsonrpc: '2.0', method: '$/cancelRequest', params: { id: 6 } });
		let resp = lsp.receive(proc);
		assert.match(6, resp.id);
		assert.match(-32800, resp.error?.code);
	});
});
