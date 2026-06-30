import * as fs from 'fs';
import * as io from 'language_server.io';

let _buf = '';

export function startListening(dispatch, onEof) {
	// io.onReadable handles the uloop wiring and the raw, non-blocking reads
	// (see language_server/io.uc and native.c). Here we only reassemble the
	// Content-Length framed messages from the delivered byte chunks.
	io.onReadable(fs.stdin, function(chunk) {
		_buf += chunk;

		while (true) {
			let headerEnd = index(_buf, '\r\n\r\n');
			if (headerEnd < 0) break;
			let header = substr(_buf, 0, headerEnd);
			let m = match(header, /Content-Length: ([0-9]+)/);
			if (!m) die(sprintf('missing Content-Length in header: %s', header));
			let bodyLen = +m[1];
			let msgStart = headerEnd + 4;
			if (length(_buf) < msgStart + bodyLen) break;
			let body = substr(_buf, msgStart, bodyLen);
			_buf = substr(_buf, msgStart + bodyLen);
			dispatch(body);
		}
	}, onEof);
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
