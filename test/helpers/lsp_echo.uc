/*
 * Minimal LSP-framing echo server used by rpc_client unit tests.
 * Reads Content-Length-framed messages from stdin and echoes them back
 * to stdout unchanged.
 */
import * as fs from 'fs';

function read_exact(n) {
	let buf = '';

	while (length(buf) < n) {
		let chunk = fs.stdin.read(n - length(buf));

		if (chunk === null || length(chunk) === 0)
			exit(0);

		buf += chunk;
	}

	return buf;
}

while (true) {
	let header = '';

	while (index(header, '\r\n\r\n') < 0) {
		let ch = fs.stdin.read(1);

		if (ch === null || length(ch) === 0)
			exit(0);

		header += ch;
	}

	let m = match(header, /Content-Length: ([0-9]+)/);

	if (!m)
		exit(1);

	let body = read_exact(+m[1]);

	fs.stdout.write(sprintf('Content-Length: %d\r\n\r\n%s', length(body), body));
	fs.stdout.flush();
}
