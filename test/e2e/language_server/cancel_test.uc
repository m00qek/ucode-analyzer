import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';
import * as fs from 'fs';

let proc;

beforeEach(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

afterEach(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

function cancel(id) {
	return { jsonrpc: '2.0', method: '$/cancelRequest', params: { id } };
}

// A workspace big enough that scanning it outlasts a request round trip (the
// fixture workspace is scanned in milliseconds).
function bigWorkspace() {
	let ws = fs.mkdtemp('/tmp/cancel-XXXXXX');
	let body = '';
	for (let i = 0; i < 40; i++)
		body += sprintf("function f%d(a, b) {\n\tlet x = a + b;\n\tif (x > %d) return x;\n\treturn [a, b];\n}\n", i, i);
	for (let i = 0; i < 100; i++)
		fs.writefile(sprintf('%s/m%03d.uc', ws, i), body);
	return ws;
}

describe('$/cancelRequest', () => {
	it('answers a queued request as cancelled without running it', () => {
		lsp.sendAll(proc, [
			{ jsonrpc: '2.0', id: 5, method: 'workspace/symbol', params: { query: '' } },
			cancel(5),
		]);
		let resp = lsp.receive(proc);
		assert.match(5, resp.id);
		assert.match(-32800, resp.error?.code);
	});

	it('stops a workspace scan in progress', () => {
		let ws = bigWorkspace();
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect(ws);
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 7, method: 'workspace/diagnostic',
			params: { previousResultIds: [] } });
		// Once this is answered, the scan above has started.
		lsp.send(proc, { jsonrpc: '2.0', id: 8, method: 'workspace/symbol', params: { query: 'zzz' } });
		assert.match(8, lsp.receive(proc).id);

		lsp.send(proc, cancel(7));
		let resp = lsp.receive(proc);
		assert.match(7, resp.id);
		assert.match(-32800, resp.error?.code);

		// No late result for 7 follows.
		lsp.send(proc, { jsonrpc: '2.0', id: 9, method: 'workspace/symbol', params: { query: 'zzz' } });
		let late = lsp.receive(proc);
		system(['rm', '-rf', ws]);
		assert.match(9, late.id);
	});

	it('ignores the cancellation of a request already answered', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'workspace/symbol', params: { query: 'zzz' } });
		assert.match(3, lsp.receive(proc).id);
		lsp.send(proc, cancel(3));
		lsp.send(proc, { jsonrpc: '2.0', id: 4, method: 'workspace/symbol', params: { query: 'zzz' } });
		assert.match(4, lsp.receive(proc).id);
	});
});
