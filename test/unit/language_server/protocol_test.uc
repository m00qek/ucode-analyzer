import { describe, it, assert } from 'utest';
import { drainFrames } from 'ucode_analyzer.language_server.protocol';

// A Content-Length framed message. length() is a byte count, so the header
// carries the body's byte length (what the reassembler must honor).
function frame(body) {
	return sprintf('Content-Length: %d\r\n\r\n%s', length(body), body);
}

describe('protocol — drainFrames (Content-Length reassembly)', () => {
	it('extracts a single complete message', () => {
		let r = drainFrames(frame('{"a":1}'));
		assert.match({ frames: [ '{"a":1}' ], rest: '', bad: [] }, r);
	});

	it('extracts multiple messages from one buffer', () => {
		let r = drainFrames(frame('one') + frame('two'));
		assert.match({ frames: [ 'one', 'two' ], rest: '', bad: [] }, r);
	});

	it('keeps an incomplete header as rest (no blank-line terminator yet)', () => {
		let r = drainFrames('Content-Length: 5\r\n');
		assert.match({ frames: [], rest: 'Content-Length: 5\r\n', bad: [] }, r);
	});

	it('keeps a complete header whose body is not yet fully delivered', () => {
		let buf = 'Content-Length: 10\r\n\r\nabc';   // only 3 of 10 body bytes
		let r = drainFrames(buf);
		assert.match({ frames: [], rest: buf, bad: [] }, r);
	});

	it('emits the ready message and holds the partial next one', () => {
		let buf = frame('ready') + 'Content-Length: 99\r\n\r\npartial';
		let r = drainFrames(buf);
		assert.match({ frames: [ 'ready' ], rest: 'Content-Length: 99\r\n\r\npartial', bad: [] }, r);
	});

	it('uses the byte length for multi-byte UTF-8 bodies', () => {
		// é is two bytes; a char-based (rather than byte-based) length would
		// misalign the frame boundary and corrupt the following message.
		let body = '{"s":"café"}';
		let r = drainFrames(frame(body) + frame('next'));
		assert.match({ frames: [ body, 'next' ], rest: '', bad: [] }, r);
	});

	it('tolerates additional headers before Content-Length', () => {
		let buf = 'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n' +
		          'Content-Length: 2\r\n\r\n{}';
		let r = drainFrames(buf);
		assert.match({ frames: [ '{}' ], rest: '', bad: [] }, r);
	});

	it('drops a header without Content-Length and reads on', () => {
		let r = drainFrames('Content-Type: x\r\n\r\n' + frame('{}'));
		assert.match(['{}'], r.frames);
		assert.match(['Content-Type: x'], r.bad);
		assert.match('', r.rest);
	});

	it('reads the Content-Length header in any case', () => {
		let r = drainFrames('content-length: 2\r\n\r\n{}');
		assert.match(['{}'], r.frames);
		assert.match([], r.bad);
	});

	it('returns no frames for an empty buffer', () => {
		let r = drainFrames('');
		assert.match({ frames: [], rest: '', bad: [] }, r);
	});
});
