import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Open the marked text at uri.
function openMarked(uri, marked) {
	let src = cursors(marked);
	lsp.open(proc, uri, src.text);
	return src;
}

// Prepare the call hierarchy at position.
function prepare(id, uri, position) {
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/prepareCallHierarchy', params: {
		textDocument: { uri }, position,
	}});
	return lsp.receive(proc);
}

describe('textDocument/prepareCallHierarchy', () => {

	it('returns a CallHierarchyItem when cursor is on a function declaration name', () => {
		let src = openMarked('file:///t.uc', "function $0$1greet$2(name) { return name; }\ngreet('x');\n");

		let resp = prepare(1, 'file:///t.uc', src.at[0]);
		assert.match(1, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		let item = resp.result[0];
		assert.match('greet', item.name);
		assert.match(12, item.kind);  // Function
		assert.match('file:///t.uc', item.uri);
		assert.match({ start: src.at[1], end: src.at[2] }, item.selectionRange);
	});

	it('returns null when cursor is not on a function identifier', () => {
		let src = openMarked('file:///t2.uc', "let $0x = 1;\nx;\n");  // x is not a function

		let resp = prepare(2, 'file:///t2.uc', src.at[0]);
		assert.match(null, resp.result);
	});

	it('returns an item when cursor is on a call site for a local function', () => {
		let src = openMarked('file:///t3.uc', "function foo() {}\nf$0oo();\n");

		let resp = prepare(3, 'file:///t3.uc', src.at[0]);
		assert.match('foo', resp.result[0].name);
	});

	it('cross-file: cursor on a use of an imported function resolves to its declaration', () => {
		let greet = openMarked(fixture.uri('greet.uc'), "function $1greet$2() {}\nexport { greet };\n");
		let caller = fixture.uri('pc_caller.uc');
		// Cursor on the `greet` call in the importer — it has no local declaration.
		let src = openMarked(caller, "import { greet } from 'greet';\ng$0reet();\n");

		let resp = prepare(5, caller, src.at[0]);
		assert.match(5, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match('greet', resp.result[0].name);
		assert.match(fixture.uri('greet.uc'), resp.result[0].uri);  // the declaring file
		assert.match({ start: greet.at[1], end: greet.at[2] }, resp.result[0].selectionRange);
	});

});

describe('callHierarchy/incomingCalls', () => {

	it('returns the enclosing function for a call site', () => {
		let src = openMarked('file:///t4.uc', "function $0foo() {}\nfunction bar() { foo(); }\nbar;\n");

		// Prepare hierarchy for 'foo'
		let item = prepare(1, 'file:///t4.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		assert.match('bar', resp.result[0].from.name);
		assert.match(1, length(resp.result[0].fromRanges));
	});

	it('cross-file: groups an importer\'s multiple call sites without duplicating ranges', () => {
		// greet.uc exports greet(); open it plus an importer that calls it 3×.
		let src = openMarked(fixture.uri('greet.uc'), "function $0greet() {}\nexport { greet };\n");
		let caller = fixture.uri('caller.uc');
		lsp.open(proc, caller, "import { greet } from 'greet';\ngreet(); greet(); greet();\n");

		// Prepare the hierarchy on greet's declaration in the fixture.
		let item = prepare(1, fixture.uri('greet.uc'), src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		// Other tests in this session may also import greet, so isolate this file's
		// entry rather than assuming it's the only caller.
		let mine = filter(resp.result, (c) => c.from.uri === caller);
		assert.match(1, length(mine));
		assert.match(3, length(mine[0].fromRanges));              // 3 calls, not 3×3
	});

	it('returns null when there are no callers', () => {
		let src = openMarked('file:///t5.uc', "function $0unused() {}\n");

		let item = prepare(1, 'file:///t5.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('groups multiple call sites from the same caller', () => {
		let src = openMarked('file:///t6.uc', "function $0foo() {}\nfunction bar() { foo(); foo(); }\nbar;\n");

		let item = prepare(1, 'file:///t6.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));           // one caller (bar)
		assert.match(2, length(resp.result[0].fromRanges));  // two call sites
	});

});

describe('callHierarchy/outgoingCalls', () => {

	it('returns functions called by the given function', () => {
		let src = openMarked('file:///t7.uc', "function foo() {}\nfunction $0bar() { foo(); }\nbar;\n");

		let item = prepare(1, 'file:///t7.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));
		assert.match('foo', resp.result[0].to.name);
		assert.match(1, length(resp.result[0].fromRanges));
	});

	it('returns null when the function has no outgoing calls', () => {
		let src = openMarked('file:///t8.uc', "function $0leaf() { return 42; }\nleaf;\n");

		let item = prepare(1, 'file:///t8.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('deduplicates repeated calls to the same function', () => {
		let src = openMarked('file:///t9.uc', "function foo() {}\nfunction $0bar() { foo(); foo(); }\nbar;\n");

		let item = prepare(1, 'file:///t9.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));           // one callee (foo)
		assert.match(2, length(resp.result[0].fromRanges));  // two call sites
	});

});
