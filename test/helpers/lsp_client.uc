import * as rpc from 'rpc_client';

export function connect() {
	return rpc.connect('ucode', ['-L', '/app/src', '/app/src/ucode_language_server/lsp.uc']);
};

export function initialize(proc) {
	rpc.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
	return rpc.receive(proc);
};

export function shutdown(proc) {
	rpc.send(proc, { jsonrpc: '2.0', id: 0, method: 'shutdown', params: null });
	rpc.receive(proc);
	rpc.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
};

export const send = rpc.send;
export const receive = rpc.receive;
export const close = rpc.close;
