import * as native from 'rpc_client.native';

function write_all(proc, data) {
	let off = 0;
	let len = length(data);
	while (off < len)
		off += proc.write_raw(substr(data, off));
};

function read_exact(proc, n) {
	let parts = [];
	let got = 0;
	while (got < n) {
		let chunk = proc.read_raw(n - got);
		if (length(chunk) === 0)
			die('unexpected EOF reading message body');
		push(parts, chunk);
		got += length(chunk);
	}
	return join('', parts);
};

function read_header(proc) {
	let buf = '';
	while (index(buf, '\r\n\r\n') < 0) {
		let ch = proc.read_raw(1);
		if (length(ch) === 0)
			return null;
		buf += ch;
	}
	return buf;
};

function read_message(proc) {
	let header = read_header(proc);
	if (header === null)
		return null;
	let m = match(header, /Content-Length: ([0-9]+)/);
	if (!m)
		die(sprintf('missing Content-Length in header: %s', header));
	return json(read_exact(proc, +m[1]));
};

export function spawn(path, args) {
	return native.spawn(path, args ?? []);
};

export function send(proc, obj) {
	let body = sprintf('%J', obj);
	write_all(proc, sprintf('Content-Length: %d\r\n\r\n%s', length(body), body));
};

export function close(proc) {
	return proc.close();
};

// Skip server-to-client notifications (no id field) and return the next response.
export function receive(proc) {
	while (true) {
		let msg = read_message(proc);
		if (msg === null || msg.id !== null) return msg;
	}
};

// Skip responses and return the next server-to-client notification.
export function receiveNotification(proc) {
	while (true) {
		let msg = read_message(proc);
		if (msg === null || msg.id === null) return msg;
	}
};

export function connect() {
	return spawn('ucode', [
		'-L', '/app/src',
		'/app/src/ucode-language-server.uc',
		'--config', '/tmp',
		'--workspace', '/app',
	]);
};

export function initialize(proc) {
	send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
	let resp = receive(proc);
	send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });
	return resp;
};

export function shutdown(proc) {
	send(proc, { jsonrpc: '2.0', id: 0, method: 'shutdown', params: null });
	let resp = receive(proc);
	if (resp.error !== null)
		die(sprintf('shutdown failed: %J', resp.error));
	send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
	return resp;
};
