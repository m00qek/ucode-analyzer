import * as fs from 'fs';
import * as io from 'language_server.io';

let _buf = '';

// Pull every complete Content-Length framed message out of `buf`, returning
// { frames: [body, ...], rest, bad: [header, ...] }. `rest` is the leftover tail
// (an incomplete header or a body not yet fully delivered) to be re-fed with the
// next chunk. A header without Content-Length is dropped into `bad` and reading
// resumes after it; header names are case-insensitive.
// Content-Length is a BYTE count and substr/length here are byte-based, so the
// body extraction stays correct for multi-byte UTF-8 payloads. Pure and
// stateless so the framing can be tested without the io/uloop wiring.
export function drainFrames(buf) {
	let frames = [];
	let bad = [];
	while (true) {
		let headerEnd = index(buf, '\r\n\r\n');
		if (headerEnd < 0) break;
		let header = substr(buf, 0, headerEnd);
		let msgStart = headerEnd + 4;
		let m = match(header, /content-length: *([0-9]+)/i);
		if (!m) {
			push(bad, header);
			buf = substr(buf, msgStart);
			continue;
		}
		let bodyLen = +m[1];
		if (length(buf) < msgStart + bodyLen) break;
		push(frames, substr(buf, msgStart, bodyLen));
		buf = substr(buf, msgStart + bodyLen);
	}
	return { frames, rest: buf, bad };
};

// Call onFrames with the bodies of the messages each read completes, all at
// once, so the caller sees a whole batch (a request and its cancellation).
export function startListening(onFrames, onEof) {
	// io.onReadable handles the uloop wiring and the raw, non-blocking reads
	// (see language_server/io.uc and native.c). Here we only reassemble the
	// Content-Length framed messages from the delivered byte chunks.
	io.onReadable(fs.stdin, function(chunk) {
		_buf += chunk;
		let r = drainFrames(_buf);
		_buf = r.rest;
		for (let header in r.bad)
			warn(sprintf('ucode-ls: dropped a message header without Content-Length: %J\n', header));
		if (length(r.frames))
			onFrames(r.frames);
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
