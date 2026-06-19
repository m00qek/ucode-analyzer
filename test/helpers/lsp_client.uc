import * as rpc from 'rpc_client';

export function connect() {
	return rpc.connect('ucode', [
		'-L', '/app/src',
		'/app/src/ucode-language-server.uc',
		'--config', '/tmp',
		'--workspace', '/app',
	]);
};

export function initialize(proc) {
	rpc.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
	let resp = rpc.receive(proc);
	rpc.send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });
	return resp;
};

export function shutdown(proc) {
	rpc.send(proc, { jsonrpc: '2.0', id: 0, method: 'shutdown', params: null });
	let resp = rpc.receive(proc);

	if (resp.error !== null)
		die(sprintf('shutdown failed: %J', resp.error));

	rpc.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });

	return resp;
};

export const send = rpc.send;
export const close = rpc.close;

// Skip server-to-client notifications (no id field) and return the next response.
export function receive(proc) {
	while (true) {
		let msg = rpc.receive(proc);
		if (msg === null || msg.id !== null) return msg;
	}
};

// Skip responses and return the next server-to-client notification.
export function receiveNotification(proc) {
	while (true) {
		let msg = rpc.receive(proc);
		if (msg === null || msg.id === null) return msg;
	}
};
