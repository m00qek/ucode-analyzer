import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

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
		assert.match(9, lsp.receive(proc).id);
	});

	it('ignores the cancellation of a request already answered', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'workspace/symbol', params: { query: 'zzz' } });
		assert.match(3, lsp.receive(proc).id);
		lsp.send(proc, cancel(3));
		lsp.send(proc, { jsonrpc: '2.0', id: 4, method: 'workspace/symbol', params: { query: 'zzz' } });
		assert.match(4, lsp.receive(proc).id);
	});
});
