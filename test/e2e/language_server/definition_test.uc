import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/definition', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns the location of a local declaration', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 5;\nx;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // 'x' reference on line 1
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(0, resp.result.range.start.line);       // declaration on line 0
		assert.match(4, resp.result.range.start.character);  // 'x' at col 4
	});

	it('returns null for an unknown identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "foo;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('returns the location of a local function declaration', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function greet() {}\ngreet;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(0, resp.result.range.start.line);
		assert.match(9, resp.result.range.start.character);  // 'greet' after 'function '
	});

	it('returns null for a non-identifier node', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 5;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },  // 'l' in 'let' — anonymous token
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('follows a named import to an inline export function', () => {
		// parse is at line 75 col 16 in tree_sitter.uc (after 'export function ')
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { parse } from 'tree_sitter';\nparse;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.uri, 'tree_sitter') >= 0);
		assert.match(75, resp.result.range.start.line);
		assert.match(16, resp.result.range.start.character);
	});

	it('follows a named import to a function declared via export { name }', () => {
		// test/fixtures/greet.uc: function greet() {}  export { greet };
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { greet } from 'fixtures.greet';\ngreet;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.uri, 'greet') >= 0);
		assert.match(0, resp.result.range.start.line);
		assert.match(9, resp.result.range.start.character);  // 'greet' after 'function '
	});

	it('returns the location of an inline export let declaration', () => {
		// 'export let count = 0' — 'count' starts at col 11 (after 'export let ')
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "export let count = 0;\ncount;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(0, resp.result.range.start.line);
		assert.match(11, resp.result.range.start.character);
	});

	it('returns the location of an inline export function declaration', () => {
		// 'export function greet' — 'greet' starts at col 16 (after 'export function ')
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "export function greet() {}\ngreet;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(0, resp.result.range.start.line);
		assert.match(16, resp.result.range.start.character);
	});

	it('jumps to parameter declaration when cursor is on a parameter reference', () => {
		// 'ts' is at col 15 in 'function parse(ts, opts)'
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "function parse(ts, opts) {\nts;\n}" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // 'ts' reference inside body
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(0, resp.result.range.start.line);
		assert.match(15, resp.result.range.start.character);
	});

	it('jumps to module top when cursor is on a namespace import alias', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // 'ts' alias reference
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.uri, 'tree_sitter') >= 0);
		assert.match(0, resp.result.range.start.line);
		assert.match(0, resp.result.range.start.character);
	});

	it('jumps to the export when cursor is on a member expression property', () => {
		// cursor on 'parse' (col 3) in 'ts.parse' — should jump to parse in tree_sitter.uc
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts.parse;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 3 },  // 'parse' in 'ts.parse'
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.uri, 'tree_sitter') >= 0);
		assert.match(75, resp.result.range.start.line);
		assert.match(16, resp.result.range.start.character);
	});

	it('returns null for a property not exported by the module', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts.doesNotExist;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 3 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('follows a renamed import to the original declaration', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { parse as p } from 'tree_sitter';\np;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.uri, 'tree_sitter') >= 0);
		assert.match(75, resp.result.range.start.line);
		assert.match(16, resp.result.range.start.character);
	});
});
