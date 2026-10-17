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

describe('textDocument/codeAction', () => {

	it('returns a quickfix for == that replaces it with ===', () => {
		// Open a file with == so the server reports a hint diagnostic.
		lsp.open(proc, 'file:///t.uc', "let x = 1;\nlet y = x == 1;\ny;\n");
		let diags = lsp.documentDiagnostics(proc, 'file:///t.uc').items;
		let hint = filter(diags, (d) => d.severity === 4)[0];
		assert.match(true, hint !== null);

		// Send the hint back as context for codeAction.
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t.uc' },
			range: hint.range,
			context: { diagnostics: [hint] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, type(resp.result) === 'array');
		assert.match(1, length(resp.result));

		let action = resp.result[0];
		assert.match('quickfix', action.kind);
		assert.match(true, action.isPreferred);
		assert.match('===', action.edit.changes['file:///t.uc'][0].newText);
	});

	it('returns a quickfix for != that replaces it with !==', () => {
		lsp.open(proc, 'file:///t2.uc', "let x = 1;\nlet y = x != 1;\ny;\n");
		let diags = lsp.documentDiagnostics(proc, 'file:///t2.uc').items;
		let hint = filter(diags, (d) => d.severity === 4)[0];

		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t2.uc' },
			range: hint.range,
			context: { diagnostics: [hint] },
		}});

		let resp = lsp.receive(proc);
		assert.match('!==', resp.result[0].edit.changes['file:///t2.uc'][0].newText);
	});

	it('returns null when context diagnostics are empty', () => {
		lsp.open(proc, 'file:///t3.uc', "let x = 1;\nx;\n");

		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t3.uc' },
			range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
			context: { diagnostics: [] },
		}});

		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('remove_unused_import: removes the whole import statement', () => {
		let uri = 'file:///t4.uc';
		lsp.open(proc, uri, "import { unusedFn } from 'utest';\nlet x = 1;\nx;\n");
		let diags = lsp.documentDiagnostics(proc, uri).items;
		let diag = filter(diags, (d) => d.code === 'unused-import')[0];
		assert.match(true, diag !== null);

		lsp.send(proc, { jsonrpc: '2.0', id: 4, method: 'textDocument/codeAction', params: {
			textDocument: { uri },
			range: diag.range,
			context: { diagnostics: [diag] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		let action = resp.result[0];
		assert.match('quickfix', action.kind);
		assert.match(true, action.isPreferred);
		let edit = action.edit.changes[uri][0];
		assert.match('', edit.newText);
		// Whole import line removed: starts at line 0 col 0, ends at line 1 col 0
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.start.character);
		assert.match(1, edit.range.end.line);
		assert.match(0, edit.range.end.character);
	});

	it('remove_unused_import: removes only the unused specifier from a multi-import', () => {
		let uri = 'file:///t5.uc';
		lsp.open(proc, uri, "import { describe, it } from 'utest';\nit;\n");
		let diags = lsp.documentDiagnostics(proc, uri).items;
		let diag = filter(diags, (d) => d.code === 'unused-import')[0];
		assert.match(true, diag !== null);

		lsp.send(proc, { jsonrpc: '2.0', id: 5, method: 'textDocument/codeAction', params: {
			textDocument: { uri },
			range: diag.range,
			context: { diagnostics: [diag] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		let edit = resp.result[0].edit.changes[uri][0];
		assert.match('', edit.newText);
		// Only the specifier is removed, not the whole line
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.end.line);
	});

	it('remove_duplicate_key: removes the duplicate pair', () => {
		let uri = 'file:///t6.uc';
		lsp.open(proc, uri, "let x = { a: 1, b: 2, a: 3 };\nx;\n");
		let diags = lsp.documentDiagnostics(proc, uri).items;
		let diag = filter(diags, (d) => d.code === 'duplicate-key')[0];
		assert.match(true, diag !== null);

		lsp.send(proc, { jsonrpc: '2.0', id: 6, method: 'textDocument/codeAction', params: {
			textDocument: { uri },
			range: diag.range,
			context: { diagnostics: [diag] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		let action = resp.result[0];
		assert.match('quickfix', action.kind);
		assert.match(true, action.isPreferred);
		let edit = action.edit.changes[uri][0];
		assert.match('', edit.newText);
		// Edit is on line 0 (single-line object literal)
		assert.match(0, edit.range.start.line);
	});

	it('change_const_to_let: replaces the const keyword with let', () => {
		let uri = 'file:///t7.uc';
		lsp.open(proc, uri, "const x = 1;\nx = 2;\n");
		let diags = lsp.documentDiagnostics(proc, uri).items;
		let diag = filter(diags, (d) => d.code === 'const-assignment')[0];
		assert.match(true, diag !== null);

		lsp.send(proc, { jsonrpc: '2.0', id: 7, method: 'textDocument/codeAction', params: {
			textDocument: { uri },
			range: diag.range,
			context: { diagnostics: [diag] },
		}});

		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		let action = resp.result[0];
		assert.match('quickfix', action.kind);
		assert.match(false, action.isPreferred);
		let edit = action.edit.changes[uri][0];
		assert.match('let', edit.newText);
		// const keyword is at line 0, character 0
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.start.character);
	});

	it('change_const_to_let: deduplicates when multiple assignments to same const', () => {
		let uri = 'file:///t8.uc';
		lsp.open(proc, uri, "const x = 1;\nx = 2;\nx = 3;\n");
		let all = lsp.documentDiagnostics(proc, uri).items;
		let diags = filter(all, (d) => d.code === 'const-assignment');
		assert.match(2, length(diags));

		lsp.send(proc, { jsonrpc: '2.0', id: 8, method: 'textDocument/codeAction', params: {
			textDocument: { uri },
			range: diags[0].range,
			context: { diagnostics: diags },
		}});

		let resp = lsp.receive(proc);
		// Two diagnostics but only one action (deduplication by const keyword position)
		assert.match(1, length(resp.result));
		assert.match('let', resp.result[0].edit.changes[uri][0].newText);
	});

	it('generate_jsdoc: offers a refactoring at a function with no doc', () => {
		lsp.open(proc, 'file:///j.uc', "function add(a, b) {\n\treturn 1;\n}\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 7, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///j.uc' },
			range: { start: { line: 0, character: 9 }, end: { line: 0, character: 9 } },
			context: { diagnostics: [] },
		}});
		let resp = lsp.receive(proc);
		assert.match(7, resp.id);
		assert.match(['Generate JSDoc'], map(resp.result ?? [], (a) => a.title));
		assert.match('refactor.rewrite', resp.result[0].kind);
		assert.match("/**\n * @param {any} a\n * @param {any} b\n * @returns {int}\n */\n",
			resp.result[0].edit.changes['file:///j.uc'][0].newText);
	});
});

