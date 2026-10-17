import { describe, it, assert, setup, teardown } from 'utest';
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

// Open the marked text at uri and return the hover text at $0.
function hoverAt(uri, marked) {
	let src = cursors(marked);
	lsp.open(proc, uri, src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
		textDocument: { uri }, position: src.at[0],
	}});
	let resp = lsp.receive(proc);
	assert.match(1, resp.id);
	return resp.result.contents.value;
}

// The hover text of a plain value: its name and type.
function typed(text) {
	return '```ucode\n' + text + '\n```';
}

describe('template type parameter propagation', () => {

	it('slice of int array yields list<int>', () => {
		assert.match(typed('r: list<int>'),
			hoverAt('file:///t.uc', "let xs = [1, 2, 3];\nlet r = slice(xs, 1);\n$0r;\n"));
	});

	it('slice of string array from split yields list<string>', () => {
		assert.match(typed('r: list<string>'),
			hoverAt('file:///t.uc', "let parts = split(\"a,b,c\", \",\");\nlet r = slice(parts, 1);\n$0r;\n"));
	});

	it('slice inside @template K function preserves K in return type', () => {
		assert.match(typed('r: list<K>'), hoverAt('file:///t.uc',
			"/** @template K\n * @param {list<K>} items\n */\nfunction head(items) {\n    let r = slice(items, 1);\n    $0r;\n}\n"));
	});

	it('filter inside @template K function preserves K in return type', () => {
		assert.match(typed('r: list<K>'), hoverAt('file:///t.uc',
			"/** @template K\n * @param {list<K>} items\n */\nfunction nonempty(items) {\n    let r = filter(items, length);\n    $0r;\n}\n"));
	});
});

describe('export function visible to later code in same file', () => {
	it('calling a sibling export function resolves to its return type', () => {
		assert.match(typed('r: string'), hoverAt('file:///export_fn_scope.uc',
			"/**\n * @returns {string}\n */\nexport function tag(x) { return '' + x; };\nexport function caller(v) {\n    let r = tag(v);\n    $0r;\n};\n"));
	});
});

describe('nested block scope — let inside for-in body', () => {
	it('let declared inside a for-in body resolves to its initializer type', () => {
		assert.match(typed('k: string'), hoverAt('file:///nested_scope.uc',
			"/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let item in items) {\n    let k = tag(item);\n    $0k;\n}\n"));
	});

	it('let declared inside a doubly-nested for-in body resolves correctly', () => {
		assert.match(typed('k: string'), hoverAt('file:///double_nested.uc',
			"/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let outer in items) {\n    for (let inner in outer) {\n        let k = tag(inner);\n        $0k;\n    }\n}\n"));
	});
});
