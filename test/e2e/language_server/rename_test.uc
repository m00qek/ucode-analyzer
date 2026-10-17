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

describe('textDocument/rename', () => {

	it('returns workspace edit replacing all occurrences', () => {
		lsp.open(proc, 'file:///t.uc', "let count = 0;\ncount;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
			newName: 'total',
		}});

		let resp = lsp.receive(proc);
		let edits = resp.result.changes['file:///t.uc'];

		assert.match(1, resp.id);
		assert.match(2, length(edits));
		for (let e in edits)
			assert.match('total', e.newText);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
			newName: 'y',
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('cross-file: rename from importer propagates edits to declaring module', () => {
		let uri = 'file:///t_xrename.uc';
		let text = "import { parse } from 'tree_sitter';\nparse();\n";
		lsp.open(proc, uri, text);
		lsp.send(proc, { jsonrpc: '2.0', id: 10, method: 'textDocument/rename', params: {
			textDocument: { uri },
			position: { line: 1, character: 0 },  // 'parse' in 'parse();'
			newName: 'parseDoc',
		}});

		let resp = lsp.receive(proc);

		assert.match(10, resp.id);
		assert.match(true, resp.result !== null);
		let changes = resp.result.changes;

		// Importing file must have edits (import specifier + call).
		assert.match(true, type(changes[uri]) === 'array');
		assert.match(true, length(changes[uri]) >= 1);

		// tree_sitter.uc must also have edits (the export declaration and internal uses).
		let tsUri = 'file:///app/src/tree_sitter.uc';
		assert.match(true, type(changes[tsUri]) === 'array');
		assert.match(true, length(changes[tsUri]) >= 1);
		for (let e in (changes[tsUri] ?? []))
			assert.match('parseDoc', e.newText);
	});

	it('renames only the binding in scope, not same-named identifiers in other scopes', () => {
		// Two functions each declare a local `n`.  Renaming one must not affect the other.
		let text = "function a(n) { return n; }\nfunction b(n) { return n; }\n";
		lsp.open(proc, 'file:///t.uc', text);
		lsp.send(proc, { jsonrpc: '2.0', id: 2, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 11 },  // `n` parameter in function a
			newName: 'num',
		}});

		let resp = lsp.receive(proc);
		let edits = resp.result.changes['file:///t.uc'];

		// Only 2 edits: parameter declaration + use inside a.  Function b unchanged.
		assert.match(2, length(edits));
		for (let e in edits) {
			assert.match('num', e.newText);
			assert.match(0, e.range.start.line);
		}
	});
});
