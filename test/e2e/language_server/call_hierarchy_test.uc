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
		lsp.open(proc, 'file:///t.uc', "function greet(name) { return name; }\ngreet('x');\n");

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
		lsp.open(proc, 'file:///t2.uc', "let x = 1;\nx;\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t2.uc' },
			position: { line: 0, character: 4 },  // cursor on 'x' (not a function)
		}});
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('returns an item when cursor is on a call site for a local function', () => {
		lsp.open(proc, 'file:///t3.uc', "function foo() {}\nfoo();\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///t3.uc' },
			position: { line: 1, character: 1 },  // cursor on 'foo' call site
		}});
		let resp = lsp.receive(proc);
		assert.match('foo', resp.result[0].name);
	});

	it('cross-file: cursor on a use of an imported function resolves to its declaration', () => {
		lsp.open(proc, 'file:///app/test/fixtures/greet.uc', "function greet() {}\nexport { greet };\n");
		lsp.open(proc, 'file:///app/pc_caller.uc', "import { greet } from 'fixtures.greet';\ngreet();\n");

		// Cursor on the `greet` call in the importer — it has no local declaration.
		lsp.send(proc, { jsonrpc: '2.0', id: 5, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///app/pc_caller.uc' },
			position: { line: 1, character: 1 },
		}});
		let resp = lsp.receive(proc);
		assert.match(5, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match('greet', resp.result[0].name);
		assert.match('file:///app/test/fixtures/greet.uc', resp.result[0].uri);  // the declaring file
	});

});

describe('callHierarchy/incomingCalls', () => {

	it('returns the enclosing function for a call site', () => {
		lsp.open(proc, 'file:///t4.uc', "function foo() {}\nfunction bar() { foo(); }\nbar;\n");

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

	it('cross-file: groups an importer\'s multiple call sites without duplicating ranges', () => {
		// fixtures/greet.uc exports greet(); open it plus an importer that calls it 3×.
		lsp.open(proc, 'file:///app/test/fixtures/greet.uc', "function greet() {}\nexport { greet };\n");
		lsp.open(proc, 'file:///app/caller.uc', "import { greet } from 'fixtures.greet';\ngreet(); greet(); greet();\n");

		// Prepare the hierarchy on greet's declaration in the fixture.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/prepareCallHierarchy', params: {
			textDocument: { uri: 'file:///app/test/fixtures/greet.uc' },
			position: { line: 0, character: 9 },
		}});
		let item = lsp.receive(proc).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		// Other tests in this session may also import greet, so isolate this file's
		// entry rather than assuming it's the only caller.
		let mine = filter(resp.result, (c) => c.from.uri === 'file:///app/caller.uc');
		assert.match(1, length(mine));
		assert.match(3, length(mine[0].fromRanges));              // 3 calls, not 3×3
	});

	it('returns null when there are no callers', () => {
		lsp.open(proc, 'file:///t5.uc', "function unused() {}\n");

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
		lsp.open(proc, 'file:///t6.uc', "function foo() {}\nfunction bar() { foo(); foo(); }\nbar;\n");

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
		lsp.open(proc, 'file:///t7.uc', "function foo() {}\nfunction bar() { foo(); }\nbar;\n");

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
		lsp.open(proc, 'file:///t8.uc', "function leaf() { return 42; }\nleaf;\n");

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
		lsp.open(proc, 'file:///t9.uc', "function foo() {}\nfunction bar() { foo(); foo(); }\nbar;\n");

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
