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

describe('completion — snippets and @deprecated', () => {

	it('function item has insertTextFormat 2 and param snippet', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 5, character: 0 },
		}});
		let resp = lsp.receive(proc);
		let item = filter(resp.result, (i) => i.label === 'add')[0];
		assert.match(true, item !== null);
		assert.match(2, item.insertTextFormat);
		assert.match('add(${1:x}, ${2:y})', item.insertText);
	});

	it('zero-param function gets empty-parens snippet', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function ping() { return true; }\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});
		let resp = lsp.receive(proc);
		let item = filter(resp.result, (i) => i.label === 'ping')[0];
		assert.match(true, item !== null);
		assert.match('ping()', item.insertText);
	});

	it('variable items have no snippet', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});
		let resp = lsp.receive(proc);
		let item = filter(resp.result, (i) => i.label === 'count')[0];
		assert.match(true, item !== null);
		assert.match(true, item.insertText === null || item.insertText === undefined);
	});

	it('@deprecated export gets tags: [1] in import-context completion', () => {
		// fixtures/deprecated.uc exports oldFn (@deprecated) and newFn (not deprecated).
		// Opening a file that imports from it and completing inside the import braces
		// goes through exportsOfModule, which should mark oldFn with tags: [1].
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { oldFn, newFn } from 'fixtures.deprecated';\n" },
		}});
		// Cursor inside the import braces (character 10) triggers import-context path.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 10 },
		}});
		let resp = lsp.receive(proc);
		let oldItem = filter(resp.result, (i) => i.label === 'oldFn')[0];
		let newItem = filter(resp.result, (i) => i.label === 'newFn')[0];
		assert.match(true, oldItem !== null);
		assert.match(true, type(oldItem.tags) === 'array' && oldItem.tags[0] === 1);
		assert.match(true, newItem !== null);
		assert.match(true, newItem.tags === null || newItem.tags === undefined);
	});
});
