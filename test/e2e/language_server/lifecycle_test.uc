import { describe, it, assert, contains } from 'utest';
import * as lsp from 'client';
import * as fs from 'fs';
import * as fixture from 'fixture';

describe('initialize response', () => {
	it('returns capabilities and serverInfo', () => {
		let proc = lsp.connect();
		let resp = lsp.initialize(proc);
		let caps = resp.result.capabilities;

		assert.match(true, type(caps) === 'object');
		assert.match(1,    caps.textDocumentSync);
		assert.match(true, caps.hoverProvider);
		assert.match(true, caps.definitionProvider);
		assert.match(true, caps.referencesProvider);
		assert.match(true, caps.documentSymbolProvider);
		assert.match(true, caps.renameProvider !== null && caps.renameProvider !== false);
		assert.match(true, type(caps.completionProvider)    === 'object');
		assert.match(true, type(caps.signatureHelpProvider) === 'object');
		assert.match('ucode-analyzer', resp.result.serverInfo.name);

		let shutdownResp = lsp.shutdown(proc);
		assert.match(null, shutdownResp.result);
		assert.match(0, lsp.close(proc));
	});
});

// Standalone: afterEach shutdown would conflict with the server already having exited.
describe('exit behavior', () => {
	it('exit without shutdown returns non-zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(true, lsp.close(proc) !== 0);
	});

	// close() closes the server's stdin and waits for it: end of stream must
	// end the server (it used to hang once the event loop was guarded, because
	// the EOF callback's exit() reached the guard as an ordinary error).
	it('stdin EOF without shutdown exits non-zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		assert.match(true, lsp.close(proc) !== 0);
	});

	it('stdin EOF after shutdown exits zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'shutdown', params: null });
		lsp.receive(proc);
		assert.match(0, lsp.close(proc));
	});

	// The whole input is already in the pipe, writer closed, when the server
	// first polls, so the last data and the hangup arrive in one event: libubox
	// unregisters stdin on that event, and the server used to read one chunk
	// and then wait forever. Exiting 0 also proves the drain reached shutdown.
	it('input followed by an immediate close is fully read', () => {
		let input = '';
		for (let msg in [
			{ jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } },
			{ jsonrpc: '2.0', method: 'initialized', params: {} },
			{ jsonrpc: '2.0', id: 1, method: 'shutdown', params: null },
		]) {
			let body = sprintf('%J', msg);
			input += sprintf('Content-Length: %d\r\n\r\n%s', length(body), body);
		}
		let path = '/tmp/lifecycle-input.txt';
		fs.writefile(path, input);

		// A timeout returns a negative signal number instead of hanging the suite.
		let status = system(sprintf(
			'cat %s | ucode -L /app/src /app/src/ucode-analyzer.uc ' +
			'--config /tmp --workspace %s >/dev/null 2>&1', path, fixture.WORKSPACE), 30000);
		fs.unlink(path);
		assert.match(0, status);
	});
});

describe('pre-initialized guard', () => {
	it('request before initialized notification returns ServerNotInitialized (-32002)', () => {
		let proc = lsp.connect();
		// Send initialize request but NOT the initialized notification.
		lsp.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
		lsp.receive(proc);  // consume initialize response

		lsp.send(proc, {
			jsonrpc: '2.0', id: 1, method: 'textDocument/hover',
			params: { textDocument: { uri: 'file:///t.uc' }, position: { line: 0, character: 0 } },
		});
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32002, resp.error.code);

		// Now send initialized and verify the server accepts further requests.
		lsp.send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});
});

describe('workspace file watcher', () => {
	it('initialized sends client/registerCapability for *.uc watching', () => {
		let proc = lsp.connect();

		// Do the handshake manually so we can capture the server's registerCapability
		// request before lsp.initialize() would consume it.
		lsp.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
		lsp.receive(proc);  // consume initialize response
		lsp.send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });

		let req = lsp.receiveServerRequest(proc);
		assert.match('client/registerCapability', req.method);
		let reg = req.params.registrations[0];
		assert.match('workspace/didChangeWatchedFiles', reg.method);
		assert.match('**/*.uc', reg.registerOptions.watchers[0].globPattern);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'shutdown', params: null });
		lsp.receive(proc);
		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
	});

	it('workspace/didChangeWatchedFiles delete event leaves server responsive', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'workspace/didChangeWatchedFiles', params: {
			changes: [{ uri: fixture.uri('gone.uc'), type: 3 }],
		}});

		// Server must still respond to a subsequent request.
		lsp.send(proc, { jsonrpc: '2.0', id: 99, method: 'shutdown', params: null });
		let resp = lsp.receive(proc);
		assert.match(99, resp.id);
		assert.match(null, resp.error);
		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
	});
});

describe('malformed JSON resilience', () => {
	it('server sends ParseError and stays alive after malformed JSON body', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		// Send a Content-Length frame whose body is not valid JSON.
		let bad = 'not valid json!!!';
		proc.write_raw(sprintf('Content-Length: %d\r\n\r\n%s', length(bad), bad));

		// Server must respond with ParseError (-32700), not crash.
		// The ParseError has id:null; receiveNotification captures null-id messages.
		let resp = lsp.receiveNotification(proc);
		assert.match(-32700, resp.error.code);

		// Server must still respond to a valid subsequent request.
		lsp.send(proc, { jsonrpc: '2.0', id: 42, method: 'shutdown', params: null });
		let ok = lsp.receive(proc);
		assert.match(42, ok.id);
		assert.match(null, ok.error);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
	});
});

describe('malformed header resilience', () => {
	it('server drops a header without Content-Length and keeps reading', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		proc.write_raw('X-Garbage: 1\r\n\r\n');

		lsp.send(proc, { jsonrpc: '2.0', id: 42, method: 'shutdown', params: null });
		let ok = lsp.receive(proc);
		assert.match(42, ok.id);
		assert.match(null, ok.error);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
	});
});

describe('failing notification', () => {
	it('is logged to stderr and the server stays alive', () => {
		let log = fs.mkdtemp('/tmp/lifecycle-XXXXXX') + '/stderr.log';
		let proc = lsp.spawn('sh', ['-c',
			sprintf('exec ucode -L /app/src /app/src/ucode-analyzer.uc --config /tmp --workspace %s 2>%s',
				fixture.WORKSPACE, log)]);
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {} });

		lsp.send(proc, { jsonrpc: '2.0', id: 42, method: 'shutdown', params: null });
		let ok = lsp.receive(proc);
		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
		let stderr = fs.readfile(log) ?? '';
		system(['rm', '-rf', fs.dirname(log)]);
		assert.match(42, ok.id);
		assert.match(contains('ucode-analyzer: textDocument/didOpen failed: '), stderr);
	});
});

describe('post-shutdown guard', () => {
	it('request after shutdown returns InvalidRequest (-32600)', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);
		lsp.send(proc, { jsonrpc: '2.0', id: 0, method: 'shutdown', params: null });
		lsp.receive(proc);  // consume shutdown response

		lsp.send(proc, {
			jsonrpc: '2.0', id: 1, method: 'textDocument/hover',
			params: { textDocument: { uri: 'file:///t.uc' }, position: { line: 0, character: 0 } },
		});
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32600, resp.error.code);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
	});
});
