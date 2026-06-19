import { describe, it, assert } from 'utest';
import * as rpc from 'rpc_client';

describe('rpc_client', () => {
	it('close() returns 0 for a clean exit', () => {
		let proc = rpc.connect('true', []);
		assert.match(0, rpc.close(proc));
	});

	it('close() returns non-zero for a failed exit', () => {
		let proc = rpc.connect('false', []);
		assert.match(true, rpc.close(proc) !== 0);
	});

	it('close() returns a negative signal code', () => {
		let proc = rpc.connect('sh', ['-c', 'kill -KILL $$']);
		assert.match(true, rpc.close(proc) < 0);
	});

	it('receive() returns null at EOF', () => {
		let proc = rpc.connect('true', []);
		assert.match(null, rpc.receive(proc));
		rpc.close(proc);
	});

	it('send/receive round-trips a message', () => {
		let proc = rpc.connect('ucode', ['/app/test/helpers/lsp_echo.uc']);
		let msg = { jsonrpc: '2.0', id: 1, method: 'ping', params: {} };

		rpc.send(proc, msg);
		let resp = rpc.receive(proc);

		assert.match(1, resp.id);
		assert.match('ping', resp.method);

		rpc.close(proc);
	});
});
