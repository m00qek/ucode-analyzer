import { describe, it, assert, setup, teardown, is_type } from 'utest';
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

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

// The CallHierarchyItem of function `name` in uri: the declaration from marker
// a to b, its name from c to d. Its data is the server's own.
function fn(name, uri, src, a, b, c, d) {
	return {
		name, kind: 12, uri, range: span(src, a, b), selectionRange: span(src, c, d),
		data: is_type('object'),
	};
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
		let src = openMarked('file:///t.uc', "$3function $0$1greet$2(name) { return name; }$4\ngreet('x');\n");

		let resp = prepare(1, 'file:///t.uc', src.at[0]);
		assert.match(1, resp.id);
		assert.match([ fn('greet', 'file:///t.uc', src, 3, 4, 1, 2) ], resp.result);
	});

	it('returns null when cursor is not on a function identifier', () => {
		let src = openMarked('file:///t2.uc', "let $0x = 1;\nx;\n");  // x is not a function

		let resp = prepare(2, 'file:///t2.uc', src.at[0]);
		assert.match(null, resp.result);
	});

	it('returns an item when cursor is on a call site for a local function', () => {
		let src = openMarked('file:///t3.uc', "$3function $1foo$2() {}$4\nf$0oo();\n");

		let resp = prepare(3, 'file:///t3.uc', src.at[0]);
		assert.match([ fn('foo', 'file:///t3.uc', src, 3, 4, 1, 2) ], resp.result);
	});

	it('cross-file: cursor on a use of an imported function resolves to its declaration', () => {
		let greet = openMarked(fixture.uri('greet.uc'), "$3function $1greet$2() {}$4\nexport { greet };\n");
		let caller = fixture.uri('pc_caller.uc');
		// Cursor on the `greet` call in the importer — it has no local declaration.
		let src = openMarked(caller, "import { greet } from 'greet';\ng$0reet();\n");

		let resp = prepare(5, caller, src.at[0]);
		assert.match(5, resp.id);
		// In the declaring file.
		assert.match([ fn('greet', fixture.uri('greet.uc'), greet, 3, 4, 1, 2) ], resp.result);
	});

});

describe('callHierarchy/incomingCalls', () => {

	it('returns the enclosing function for a call site', () => {
		let src = openMarked('file:///t4.uc', "function $0foo() {}\n$3function $1bar$2() { $5foo$6(); }$4\nbar;\n");

		// Prepare hierarchy for 'foo'
		let item = prepare(1, 'file:///t4.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match([ {
			from: fn('bar', 'file:///t4.uc', src, 3, 4, 1, 2),
			fromRanges: [ span(src, 5, 6) ],
		} ], resp.result);
	});

	it('cross-file: groups an importer\'s multiple call sites without duplicating ranges', () => {
		// greet.uc exports greet(); open it plus an importer that calls it 3×.
		let src = openMarked(fixture.uri('greet.uc'), "function $0greet() {}\nexport { greet };\n");
		let caller = fixture.uri('caller.uc');
		let calls = cursors("import { greet } from 'greet';\n$1greet$2(); $3greet$4(); $5greet$6();\n");
		lsp.open(proc, caller, calls.text);

		// Prepare the hierarchy on greet's declaration in the fixture.
		let item = prepare(1, fixture.uri('greet.uc'), src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		// Other tests in this session may also import greet, so isolate this file's
		// entry rather than assuming it's the only caller.
		// The caller is the module itself (top-level code), with 3 calls, not 3×3.
		let start = { line: 0, character: 0 };
		assert.match([ {
			from: {
				name: 'caller.uc', kind: 2, uri: caller,   // Module
				range: { start, end: start }, selectionRange: { start, end: start },
				data: is_type('object'),
			},
			fromRanges: [ span(calls, 1, 2), span(calls, 3, 4), span(calls, 5, 6) ],
		} ], filter(resp.result, (c) => c.from.uri === caller));
	});

	it('returns null when there are no callers', () => {
		let src = openMarked('file:///t5.uc', "function $0unused() {}\n");

		let item = prepare(1, 'file:///t5.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('groups multiple call sites from the same caller', () => {
		let src = openMarked('file:///t6.uc', "function $0foo() {}\n$3function $1bar$2() { $5foo$6(); $7foo$8(); }$4\nbar;\n");

		let item = prepare(1, 'file:///t6.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/incomingCalls', params: { item } });
		let resp = lsp.receive(proc);
		// One caller (bar), with two call sites.
		assert.match([ {
			from: fn('bar', 'file:///t6.uc', src, 3, 4, 1, 2),
			fromRanges: [ span(src, 5, 6), span(src, 7, 8) ],
		} ], resp.result);
	});

});

describe('callHierarchy/outgoingCalls', () => {

	it('returns functions called by the given function', () => {
		let src = openMarked('file:///t7.uc', "$3function $1foo$2() {}$4\nfunction $0bar() { $5foo$6(); }\nbar;\n");

		let item = prepare(1, 'file:///t7.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(2, resp.id);
		assert.match([ {
			to: fn('foo', 'file:///t7.uc', src, 3, 4, 1, 2),
			fromRanges: [ span(src, 5, 6) ],
		} ], resp.result);
	});

	it('returns null when the function has no outgoing calls', () => {
		let src = openMarked('file:///t8.uc', "function $0leaf() { return 42; }\nleaf;\n");

		let item = prepare(1, 'file:///t8.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('deduplicates repeated calls to the same function', () => {
		let src = openMarked('file:///t9.uc', "$3function $1foo$2() {}$4\nfunction $0bar() { $5foo$6(); $7foo$8(); }\nbar;\n");

		let item = prepare(1, 'file:///t9.uc', src.at[0]).result[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'callHierarchy/outgoingCalls', params: { item } });
		let resp = lsp.receive(proc);
		// One callee (foo), with two call sites.
		assert.match([ {
			to: fn('foo', 'file:///t9.uc', src, 3, 4, 1, 2),
			fromRanges: [ span(src, 5, 6), span(src, 7, 8) ],
		} ], resp.result);
	});

});
