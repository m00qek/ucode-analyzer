import { describe, it, assert } from 'utest';
import * as rpc from 'rpc_client';

const LSP = ['ucode', ['-L', '/app/src', '/app/src/ucode_language_server/lsp.uc']];

describe('LSP lifecycle', () => {
	it('initialize returns capabilities', () => {
		let proc = rpc.connect(...LSP);

		rpc.send(proc, { jsonrpc: '2.0', id: 1, method: 'initialize', params: { capabilities: {} } });
		let resp = rpc.receive(proc);

		assert.match(1, resp?.id);
		assert.match(true, type(resp?.result) == 'object');

		rpc.close(proc);
	});

	it('unknown request returns MethodNotFound', () => {
		let proc = rpc.connect(...LSP);

		rpc.send(proc, { jsonrpc: '2.0', id: 1, method: 'initialize', params: { capabilities: {} } });
		rpc.receive(proc);

		rpc.send(proc, { jsonrpc: '2.0', id: 2, method: 'unknown/method', params: null });
		let resp = rpc.receive(proc);

		assert.match(2, resp?.id);
		assert.match(-32601, resp?.error?.code);

		rpc.close(proc);
	});

	it('shutdown+exit returns 0', () => {
		let proc = rpc.connect(...LSP);

		rpc.send(proc, { jsonrpc: '2.0', id: 1, method: 'initialize', params: { capabilities: {} } });
		rpc.receive(proc);

		rpc.send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });

		rpc.send(proc, { jsonrpc: '2.0', id: 2, method: 'shutdown', params: null });
		let resp = rpc.receive(proc);
		assert.match(2, resp?.id);
		assert.match(null, resp?.result);

		rpc.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, rpc.close(proc));
	});

	it('exit without shutdown returns non-zero', () => {
		let proc = rpc.connect(...LSP);

		rpc.send(proc, { jsonrpc: '2.0', id: 1, method: 'initialize', params: { capabilities: {} } });
		rpc.receive(proc);

		rpc.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(true, rpc.close(proc) != 0);
	});
});
