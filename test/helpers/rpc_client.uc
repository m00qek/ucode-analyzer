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

		if (length(chunk) == 0)
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

		if (length(ch) == 0)
			return null;

		buf += ch;
	}

	return buf;
};

export function connect(path, args) {
	return native.spawn(path, args ?? []);
};

export function send(proc, obj) {
	let body = sprintf('%J', obj);

	write_all(proc, sprintf('Content-Length: %d\r\n\r\n%s', length(body), body));
};

export function receive(proc) {
	let header = read_header(proc);

	if (header == null)
		return null;

	let m = match(header, /Content-Length: ([0-9]+)/);

	if (!m)
		die(sprintf('missing Content-Length in header: %s', header));

	return json(read_exact(proc, +m[1]));
};

export function close(proc) {
	return proc.close();
};
