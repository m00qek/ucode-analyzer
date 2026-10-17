import { describe, it, assert, setup, teardown, contains } from 'utest';
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

describe('template type parameter propagation', () => {

	it('slice of int array yields ?list<int>', () => {
		lsp.open(proc, 'file:///t.uc', "let xs = [1, 2, 3];\nlet r = slice(xs, 1);\nr;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },  // 'r' in standalone r;
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(contains('list<int>'), resp.result.contents.value);
	});

	it('slice of string array from split yields ?list<string>', () => {
		lsp.open(proc, 'file:///t.uc', "let parts = split(\"a,b,c\", \",\");\nlet r = slice(parts, 1);\nr;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(contains('list<string>'), resp.result.contents.value);
	});

	it('slice inside @template K function preserves K in return type', () => {
		// Line 0: /** @template K
		// Line 1:  * @param {list<K>} items
		// Line 2:  */
		// Line 3: function head(items) {
		// Line 4:     let r = slice(items, 1);
		// Line 5:     r;
		// Line 6: }
		let src = "/** @template K\n * @param {list<K>} items\n */\nfunction head(items) {\n    let r = slice(items, 1);\n    r;\n}\n";
		lsp.open(proc, 'file:///t.uc', src);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 5, character: 4 },  // 'r' after 4 spaces
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(contains('list<K>'), resp.result.contents.value);
	});

	it('filter inside @template K function preserves K in return type', () => {
		// Line 0: /** @template K
		// Line 1:  * @param {list<K>} items
		// Line 2:  */
		// Line 3: function nonempty(items) {
		// Line 4:     let r = filter(items, length);
		// Line 5:     r;
		// Line 6: }
		let src = "/** @template K\n * @param {list<K>} items\n */\nfunction nonempty(items) {\n    let r = filter(items, length);\n    r;\n}\n";
		lsp.open(proc, 'file:///t.uc', src);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 5, character: 4 },  // 'r' after 4 spaces
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(contains('list<K>'), resp.result.contents.value);
	});
});

describe('export function visible to later code in same file', () => {
	it('calling a sibling export function resolves to its return type', () => {
		let src = "/**\n * @returns {string}\n */\nexport function tag(x) { return '' + x; };\nexport function caller(v) {\n    let r = tag(v);\n    r;\n};\n";
		let uri = 'file:///export_fn_scope.uc';
		lsp.open(proc, uri, src);
		// 'r' on the standalone 'r;' line — line 6 (0-based), character 4
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 6, character: 4 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(contains('string'), resp.result.contents.value);
	});
});

describe('nested block scope — let inside for-in body', () => {
	it('let declared inside a for-in body resolves to its initializer type', () => {
		let src = "/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let item in items) {\n    let k = tag(item);\n    k;\n}\n";
		let uri = 'file:///nested_scope.uc';
		lsp.open(proc, uri, src);
		// 'k' on the standalone 'k;' line — line 6 (0-based), character 4
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 6, character: 4 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(contains('string'), resp.result.contents.value);
	});

	it('let declared inside a doubly-nested for-in body resolves correctly', () => {
		let src = "/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let outer in items) {\n    for (let inner in outer) {\n        let k = tag(inner);\n        k;\n    }\n}\n";
		let uri = 'file:///double_nested.uc';
		lsp.open(proc, uri, src);
		// 'k' on the standalone 'k;' line — line 7 (0-based), character 8
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 7, character: 8 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(contains('string'), resp.result.contents.value);
	});
});
