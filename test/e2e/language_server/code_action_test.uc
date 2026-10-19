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

// Open text at uri and return its diagnostics with this code.
function diagnosticsOf(uri, text, code) {
	lsp.open(proc, uri, text);
	return filter(lsp.documentDiagnostics(proc, uri).items, (d) => d.code === code);
}

// Ask for the code actions fixing diags (at the first one's range). Every
// diagnostic also offers to be disabled: those are left out unless `all`.
function actionsFor(uri, id, diags, all) {
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/codeAction', params: {
		textDocument: { uri },
		range: diags[0].range,
		context: { diagnostics: diags },
	}});
	let resp = lsp.receive(proc);
	if (!all && type(resp.result) === 'array') {
		resp.result = filter(resp.result, (a) => substr(a.title, 0, 8) !== 'Disable ');
		if (!length(resp.result)) resp.result = null;
	}
	return resp;
}

// A quickfix for diag replacing range in uri with newText.
function quickfix(title, diag, isPreferred, uri, range, newText) {
	return {
		title, kind: 'quickfix', diagnostics: [ diag ], isPreferred,
		edit: { changes: { [uri]: [ { range, newText } ] } },
	};
}

describe('textDocument/codeAction', () => {

	it('offers to disable a diagnostic on its line', () => {
		let diags = diagnosticsOf('file:///t.uc', "let x = 1;\nlet y = x == 1;\ny;\n", 'prefer-strict-equality');
		let at = { line: 1, character: 0 };
		assert.match([ { title: 'Disable prefer-strict-equality for this line', kind: 'quickfix', diagnostics: [ diags[0] ],
			edit: { changes: { 'file:///t.uc': [ { range: { start: at, end: at },
				newText: '// ucode-analyzer disable-next-line prefer-strict-equality\n' } ] } } } ],
			filter(actionsFor('file:///t.uc', 1, diags, true).result, (a) => substr(a.title, 0, 8) === 'Disable '));
	});

	it('returns a quickfix for == that replaces it with ===', () => {
		// Open a file with == so the server reports a hint diagnostic.
		let src = cursors("let x = 1;\nlet y = x $1==$2 1;\ny;\n");
		let diags = diagnosticsOf('file:///t.uc', src.text, 'prefer-strict-equality');
		let range = { start: src.at[1], end: src.at[2] };
		assert.match([ { range, severity: 4, source: 'ucode-analyzer',
			code: 'prefer-strict-equality', message: "Prefer '===' over '=='" } ], diags);

		// Send the hint back as context for codeAction.
		let resp = actionsFor('file:///t.uc', 1, diags);
		assert.match(1, resp.id);
		assert.match([
			quickfix("Replace '==' with '==='", diags[0], true, 'file:///t.uc', range, '==='),
		], resp.result);
	});

	it('returns a quickfix for != that replaces it with !==', () => {
		let src = cursors("let x = 1;\nlet y = x $1!=$2 1;\ny;\n");
		let diags = diagnosticsOf('file:///t2.uc', src.text, 'prefer-strict-equality');
		assert.match(1, length(diags));

		let resp = actionsFor('file:///t2.uc', 2, diags);
		assert.match([
			quickfix("Replace '!=' with '!=='", diags[0], true, 'file:///t2.uc',
				{ start: src.at[1], end: src.at[2] }, '!=='),
		], resp.result);
	});

	it('returns null when context diagnostics are empty', () => {
		let src = cursors("$0let x = 1;\nx;\n");
		lsp.open(proc, 'file:///t3.uc', src.text);

		lsp.send(proc, { jsonrpc: '2.0', id: 3, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///t3.uc' },
			range: { start: src.at[0], end: src.at[0] },
			context: { diagnostics: [] },
		}});

		let resp = lsp.receive(proc);
		assert.match(null, resp.result);
	});

	it('remove_unused_import: removes the whole import statement', () => {
		let uri = 'file:///t4.uc';
		let src = cursors("$1import { unusedFn } from 'utest';\n$2let x = 1;\nx;\n");
		let diags = diagnosticsOf(uri, src.text, 'unused-import');
		assert.match(1, length(diags));

		let resp = actionsFor(uri, 4, diags);
		// The whole import line, newline included
		assert.match([
			quickfix("Remove unused import 'unusedFn'", diags[0], true, uri,
				{ start: src.at[1], end: src.at[2] }, ''),
		], resp.result);
	});

	it('remove_unused_import: removes only the unused specifier from a multi-import', () => {
		let uri = 'file:///t5.uc';
		let src = cursors("import { $1describe, $2it } from 'utest';\nit;\n");
		let diags = diagnosticsOf(uri, src.text, 'unused-import');
		assert.match(1, length(diags));

		let resp = actionsFor(uri, 5, diags);
		// Only the specifier is removed, not the whole line
		assert.match([
			quickfix("Remove unused import 'describe'", diags[0], true, uri,
				{ start: src.at[1], end: src.at[2] }, ''),
		], resp.result);
	});

	it('remove_duplicate_key: removes the duplicate pair', () => {
		let uri = 'file:///t6.uc';
		let src = cursors("let x = { a: 1, b: 2$1, a: 3$2 };\nx;\n");
		let diags = diagnosticsOf(uri, src.text, 'duplicate-key');
		assert.match(1, length(diags));

		let resp = actionsFor(uri, 6, diags);
		assert.match([
			quickfix("Remove duplicate key 'a'", diags[0], true, uri,
				{ start: src.at[1], end: src.at[2] }, ''),
		], resp.result);
	});

	it('change_const_to_let: replaces the const keyword with let', () => {
		let uri = 'file:///t7.uc';
		let src = cursors("$1const$2 x = 1;\nx = 2;\n");
		let diags = diagnosticsOf(uri, src.text, 'const-assignment');
		assert.match(1, length(diags));

		let resp = actionsFor(uri, 7, diags);
		assert.match([
			quickfix("Change 'const' to 'let'", diags[0], false, uri,
				{ start: src.at[1], end: src.at[2] }, 'let'),
		], resp.result);
	});

	it('change_const_to_let: deduplicates when multiple assignments to same const', () => {
		let uri = 'file:///t8.uc';
		let src = cursors("$1const$2 x = 1;\nx = 2;\nx = 3;\n");
		let diags = diagnosticsOf(uri, src.text, 'const-assignment');
		assert.match(2, length(diags));

		let resp = actionsFor(uri, 8, diags);
		// Two diagnostics, one action, which resolves (and lists) both.
		let fix = quickfix("Change 'const' to 'let'", diags[0], false, uri,
			{ start: src.at[1], end: src.at[2] }, 'let');
		fix.diagnostics = diags;
		assert.match([ fix ], resp.result);
	});

	it('generate_jsdoc: offers a refactoring at a function with no doc', () => {
		let src = cursors("$1function $0add(a, b) {\n\treturn 1;\n}\n");
		lsp.open(proc, 'file:///j.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 7, method: 'textDocument/codeAction', params: {
			textDocument: { uri: 'file:///j.uc' },
			range: { start: src.at[0], end: src.at[0] },
			context: { diagnostics: [] },
		}});
		let resp = lsp.receive(proc);
		assert.match(7, resp.id);
		assert.match([ {
			title: 'Generate JSDoc',
			kind: 'refactor.rewrite',
			edit: { changes: { 'file:///j.uc': [ {
				range: { start: src.at[1], end: src.at[1] },
				newText: "/**\n * @param {any} a\n * @param {any} b\n * @returns {int}\n */\n",
			} ] } },
		} ], resp.result);
	});
});
