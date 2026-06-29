import * as fs from 'fs';

function read_exact(n) {
	let parts = [];
	let got = 0;

	while (got < n) {
		let chunk = fs.stdin.read(n - got);

		if (length(chunk) === 0)
			die('unexpected EOF reading message body');

		push(parts, chunk);
		got += length(chunk);
	}

	return join('', parts);
};

function read_header() {
	let buf = '';

	while (index(buf, '\r\n\r\n') < 0) {
		let ch = fs.stdin.read(1);

		if (length(ch) === 0)
			return null;

		buf += ch;
	}

	return buf;
};

export function read_message() {
	let header = read_header();

	if (header === null)
		return null;

	let m = match(header, /Content-Length: ([0-9]+)/);

	if (!m)
		die(sprintf('missing Content-Length in header: %s', header));

	return json(read_exact(+m[1]));
};

export function write_message(obj) {
	let body = sprintf('%J', obj);
	fs.stdout.write(sprintf('Content-Length: %d\r\n\r\n%s', length(body), body));
	fs.stdout.flush();
};

export function respond(id, result) {
	write_message({ jsonrpc: '2.0', id, result });
};

export function notify(method, params) {
	write_message({ jsonrpc: '2.0', method, params });
};

export function request(id, method, params) {
	write_message({ jsonrpc: '2.0', id, method, params });
};

export function error(id, code, message) {
	write_message({ jsonrpc: '2.0', id, error: { code, message } });
};
