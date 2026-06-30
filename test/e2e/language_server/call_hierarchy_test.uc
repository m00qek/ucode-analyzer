import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('textDocument/prepareCallHierarchy', () => {

	it('returns a CallHierarchyItem when cursor is on a function declaration name', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function greet(name) { return name; }\ngreet('x');\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 9 },  // cursor on 'greet'
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		let item = resp.result[0];
		assert.match('greet', item.name);
		assert.match(12, item.kind);  // Function
		assert.match('file:///t.uc', item.uri);
		assert.match(0, item.selectionRange.start.line);
	});

	it('returns null when cursor is not on a function identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t2.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nx;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t2.uc' },
			position: { line: 0, character: 4 },  // cursor on 'x' (not a function)
		}});
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('returns an item when cursor is on a call site for a local function', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t3.uc', languageId: 'ucode', version: 1,
				text: "function foo() {}\nfoo();\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t3.uc' },
			position: { line: 1, character: 1 },  // cursor on 'foo' call site
		}});
		let resp = lsp.receive(proc);
		assert.match('foo', resp.result[0].name);
	});

});

describe('callHierarchy/incomingCalls', () => {

	it('returns the enclosing function for a call site', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t4.uc', languageId: 'ucode', version: 1,
				text: "function foo() {}\nfunction bar() { foo(); }\nbar;\n" },
		}});
		lsp.receiveNotification(proc);

		// Prepare hierarchy for 'foo'
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t4.uc' },
			position: { line: 0, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		assert.match('bar', resp.result[0].from.name);
		assert.match(1, length(resp.result[0].fromRanges));
	});

	it('returns null when there are no callers', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t5.uc', languageId: 'ucode', version: 1,
				text: "function unused() {}\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t5.uc' },
			position: { line: 0, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('groups multiple call sites from the same caller', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t6.uc', languageId: 'ucode', version: 1,
				text: "function foo() {}\nfunction bar() { foo(); foo(); }\nbar;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t6.uc' },
			position: { line: 0, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));           // one caller (bar)
		assert.match(2, length(resp.result[0].fromRanges));  // two call sites
	});

});

describe('callHierarchy/outgoingCalls', () => {

	it('returns functions called by the given function', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t7.uc', languageId: 'ucode', version: 1,
				text: "function foo() {}\nfunction bar() { foo(); }\nbar;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t7.uc' },
			position: { line: 1, character: 9 },  // cursor on 'bar'
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		assert.match('foo', resp.result[0].to.name);
		assert.match(1, length(resp.result[0].fromRanges));
	});

	it('returns null when the function has no outgoing calls', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t8.uc', languageId: 'ucode', version: 1,
				text: "function leaf() { return 42; }\nleaf;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t8.uc' },
			position: { line: 0, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('deduplicates repeated calls to the same function', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t9.uc', languageId: 'ucode', version: 1,
				text: "function foo() {}\nfunction bar() { foo(); foo(); }\nbar;\n" },
		}});
		lsp.receiveNotification(proc);

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t9.uc' },
			position: { line: 1, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));           // one callee (foo)
		assert.match(2, length(resp.result[0].fromRanges));  // two call sites
	});

});
