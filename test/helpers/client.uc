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

function framed(obj) {
	let body = sprintf('%J', obj);
	return sprintf('Content-Length: %d\r\n\r\n%s', length(body), body);
}

export function send(proc, obj) {
	write_all(proc, framed(obj));
};

// Open a document, as the editor does with didOpen.
export function open(proc, uri, text, version) {
	send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
		textDocument: { uri, languageId: 'ucode', version: version ?? 1, text },
	}});
};

// Replace an open document's whole text (the server syncs full documents).
export function change(proc, uri, text, version) {
	send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
		textDocument: { uri, version }, contentChanges: [{ text }],
	}});
};

// Send several messages in one write, so the server reads them as one batch.
export function sendAll(proc, objs) {
	write_all(proc, join('', map(objs, framed)));
};

// Why the server stopped answering: its exit status, collected (the process
// is gone, so nothing else is lost by closing it).
export function gone(proc, what) {
	let status = proc.close();
	return sprintf('%s: the server exited (%s)', what,
		(status < 0) ? sprintf('killed by signal %d', -status) : sprintf('status %d', status));
};

export function close(proc) {
	return proc.close();
};

// The methods of the server-to-client requests receive() skipped, for settle().
let _skipped = [];

// Return the next response. Skips server-to-client notifications (no id) and the
// server-initiated workspace/diagnostic/refresh request, which can arrive
// between a request and its response in the pull model; settle() reports it.
export function receive(proc) {
	while (true) {
		let msg = read_message(proc);
		if (msg === null) return msg;
		if (msg.id === null) continue;                                // notification
		if (msg.method === 'workspace/diagnostic/refresh') {          // server-initiated
			push(_skipped, msg.method);
			continue;
		}
		return msg;
	}
};

// Skip responses and return the next server-to-client notification.
export function receiveNotification(proc) {
	while (true) {
		let msg = read_message(proc);
		if (msg === null || msg.id === null) return msg;
	}
};

// Read up to the response to request `id`. Returns it, with the methods of the
// server-to-client requests read on the way (workspace/diagnostic/refresh, ...).
export function receiveUntil(proc, id) {
	let requests = [];
	while (true) {
		let msg = read_message(proc);
		if (msg === null) return { response: null, requests };
		if (msg.method === null && msg.id === id) return { response: msg, requests };
		if (msg.method && msg.id !== null) push(requests, msg.method);
	}
};

// Skip responses and notifications; return the next server-to-client request (id + method both set).
export function receiveServerRequest(proc) {
	while (true) {
		let msg = read_message(proc);
		if (msg === null || (msg.id !== null && msg.method)) return msg;
	}
};

let _settleId = 90000;

// Wait past the server's diagnostic-refresh delay (500 ms), then return the
// methods of every server-to-client request it sent since the last settle():
// those receive() skipped, and those that arrive now.
export function settle(proc) {
	system('sleep 1');   // busybox sleep takes whole seconds
	let id = _settleId++;
	send(proc, { jsonrpc: '2.0', id, method: 'workspace/symbol', params: { query: 'zzz' } });
	let r = receiveUntil(proc, id);
	if (r.response === null) die(gone(proc, 'settle'));
	let seen = [ ..._skipped, ...r.requests ];
	_skipped = [];
	return seen;
};

// Wait until the server's background startup load is done: it holds
// workspace/symbol until then.
export function waitForIndex(proc) {
	let id = _settleId++;
	send(proc, { jsonrpc: '2.0', id, method: 'workspace/symbol', params: { query: 'zzz' } });
	if (receiveUntil(proc, id).response === null) die(gone(proc, 'waitForIndex'));
};

// Start a server on `workspace` (default: the fixture workspace,
// test/fixtures/workspace).
export function connect(workspace) {
	return spawn('ucode', [
		'-L', '/app/src',
		'/app/src/ucode-analyzer.uc',
		'--config', '/tmp',
		'--workspace', workspace ?? '/app/test/fixtures/workspace',
	]);
};

let _diagId = 1000;

// Pull diagnostics for a single document. Returns the DocumentDiagnosticReport
// ({ kind: 'full', resultId, items } or { kind: 'unchanged', resultId }).
export function documentDiagnostics(proc, uri, previousResultId) {
	let params = { textDocument: { uri } };
	if (previousResultId !== null)
		params.previousResultId = previousResultId;
	send(proc, { jsonrpc: '2.0', id: _diagId++, method: 'textDocument/diagnostic', params });
	let resp = receive(proc);
	if (resp === null) die(gone(proc, 'documentDiagnostics'));
	return resp.result;
};

// Pull workspace diagnostics. Returns the WorkspaceDiagnosticReport ({ items }).
export function workspaceDiagnostics(proc, previousResultIds) {
	send(proc, { jsonrpc: '2.0', id: _diagId++, method: 'workspace/diagnostic',
		params: { previousResultIds: previousResultIds ?? [] } });
	let resp = receive(proc);
	if (resp === null) die(gone(proc, 'workspaceDiagnostics'));
	return resp.result;
};

export function initialize(proc) {
	send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
	let resp = receive(proc);
	send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });
	// Server sends client/registerCapability after processing initialized; consume it so
	// subsequent receive() calls return the expected responses, not this server request.
	receiveServerRequest(proc);
	waitForIndex(proc);
	return resp;
};

export function shutdown(proc) {
	send(proc, { jsonrpc: '2.0', id: 0, method: 'shutdown', params: null });
	let resp = receive(proc);
	if (resp === null) die(gone(proc, 'shutdown'));
	if (resp.error !== null)
		die(sprintf('shutdown failed: %J', resp.error));
	send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
	return resp;
};
