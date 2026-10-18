import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';
import * as fixture from 'fixture';

let proc;

beforeEach(() => {
	proc = lsp.connect();
});

afterEach(() => {
	if (!proc) return;
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Initialize without waiting for the startup load: `msgs` go in the same
// write as initialized, so the server reads them while it indexes.
function start(msgs) {
	lsp.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize', params: { capabilities: {} } });
	lsp.receive(proc);
	lsp.sendAll(proc, [ { jsonrpc: '2.0', method: 'initialized', params: {} }, ...msgs ]);
}

// The next n responses, in arrival order (server requests skipped).
function responses(n) {
	let out = [];
	while (length(out) < n) {
		let msg = lsp.receive(proc);
		if (msg === null) die(lsp.gone(proc, 'responses'));
		if (!msg.method) push(out, msg);
	}
	return out;
}

function symbols(id) {
	return { jsonrpc: '2.0', id, method: 'workspace/symbol', params: { query: 'zzz' } };
}

function hover(id) {
	return { jsonrpc: '2.0', id, method: 'textDocument/hover',
		params: { textDocument: { uri: 'file:///none.uc' }, position: { line: 0, character: 0 } } };
}

describe('startup indexing', () => {
	it('answers a hover while a request that needs the index waits', () => {
		start([ symbols(1), hover(2) ]);
		assert.match([2, 1], map(responses(2), (r) => r.id));
	});

	it('holds diagnostics until the builtins are indexed', () => {
		// Without them, undefined-var reports nothing, and the editor would
		// not pull again until the next edit.
		let uri = fixture.uri('main.uc');
		start([
			{ jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: {
				uri, languageId: 'ucode', version: 1, text: "printf('%s', ghost);\n" } } },
			{ jsonrpc: '2.0', id: 3, method: 'textDocument/diagnostic', params: { textDocument: { uri } } },
		]);
		let r = responses(1)[0];
		assert.match(3, r.id);
		assert.match([ "'ghost' is not defined" ], map(r.result.items, (d) => d.message));
	});

	it('answers a held request cancelled during the load as cancelled', () => {
		// Once the hover is answered, the request before it is held.
		start([ symbols(4), hover(7) ]);
		assert.match(7, responses(1)[0].id);
		lsp.send(proc, { jsonrpc: '2.0', method: '$/cancelRequest', params: { id: 4 } });
		let r = responses(1)[0];
		assert.match(4, r.id);
		assert.match(-32800, r.error?.code);
	});

	it('answers the held requests on shutdown', () => {
		start([ symbols(5) ]);
		lsp.send(proc, { jsonrpc: '2.0', id: 6, method: 'shutdown', params: null });
		let rs = responses(2);
		assert.match([5, 6], map(rs, (r) => r.id));
		assert.match(-32600, rs[0].error?.code);
		assert.match(null, rs[1].result);
		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(0, lsp.close(proc));
		proc = null;
	});

	it('reports its progress to a client that supports it', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 0, method: 'initialize',
			params: { capabilities: { window: { workDoneProgress: true } } } });
		lsp.receive(proc);
		lsp.send(proc, { jsonrpc: '2.0', method: 'initialized', params: {} });

		let create = lsp.receiveServerRequest(proc);
		assert.match('window/workDoneProgress/create', create.method);
		lsp.send(proc, { jsonrpc: '2.0', id: create.id, result: null });

		let values = [];
		while (!length(values) || values[-1].kind !== 'end') {
			let msg = lsp.receiveNotification(proc);
			if (msg === null) die(lsp.gone(proc, 'progress'));
			if (msg.method !== '$/progress') continue;
			assert.match(create.params.token, msg.params.token);
			push(values, msg.params.value);
		}
		assert.match('begin', values[0].kind);
		assert.match('Indexing', values[0].title);
		assert.match(match(values[-1].message, /^[0-9]+ files$/) !== null, true);
	});
});
