import { describe, it, assert, setup, teardown, any_order } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Open the marked text and ask for completions at $0.
function completeAt(marked) {
	let src = cursors(marked);
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
		textDocument: { uri: 'file:///t.uc' },
		position: src.at[0],
	}});
	return lsp.receive(proc);
}

describe('completion — snippets and @deprecated', () => {

	it('function item has insertTextFormat 2 and param snippet', () => {
		let resp = completeAt("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n$0");
		assert.match([ {
			label: 'add', kind: 3, detail: '(x: int, y: int) => int',
			insertText: 'add(${1:x}, ${2:y})', insertTextFormat: 2,
		} ], filter(resp.result, (i) => i.label === 'add'));
	});

	it('zero-param function gets empty-parens snippet', () => {
		let resp = completeAt("function ping() { return true; }\n$0");
		assert.match([ {
			label: 'ping', kind: 3, detail: '() => boolean',
			insertText: 'ping()', insertTextFormat: 2,
		} ], filter(resp.result, (i) => i.label === 'ping'));
	});

	it('variable items have no snippet', () => {
		let resp = completeAt("let count = 0;\n$0");
		assert.match([ { label: 'count', kind: 6, detail: 'int' } ],
			filter(resp.result, (i) => i.label === 'count'));
	});

	it('@deprecated export gets tags: [1] in import-context completion', () => {
		// deprecated.uc exports oldFn (@deprecated) and newFn (not deprecated).
		// Opening a file that imports from it and completing inside the import braces
		// goes through exportsOfModule, which should mark oldFn with tags: [1].
		let resp = completeAt("import { o$0ldFn, newFn } from 'deprecated';\n");
		// Inside import braces an item is the name alone, not a call.
		let item = (label) => ({ label, kind: 3, detail: '() => ?', documentation: null });
		assert.match(any_order([ { ...item('oldFn'), tags: [ 1 ] }, item('newFn') ]), resp.result);
	});
});
