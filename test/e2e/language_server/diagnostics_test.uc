import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'client';

describe('textDocument/publishDiagnostics', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('sends notification with error diagnostic for unresolvable import', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { foo } from 'no_such_module';" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		assert.match('file:///t.uc', notif.params.uri);
		// Expect at least one ERROR-severity diagnostic for the bad import.
		// (An unused-import WARNING for 'foo' may also be present.)
		let errDiags = filter(notif.params.diagnostics, (d) => d.severity === 1);
		assert.match(true, length(errDiags) >= 1);
	});

	it('sends notification with empty diagnostics for a valid file', () => {
		// All declarations are used, no syntax errors, no bad imports.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nx;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		assert.match(0, length(notif.params.diagnostics));
	});

	it('warns for an undefined identifier reference', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = ghost;\n" },
		}});

		let notif = lsp.receiveNotification(proc);
		let diags = notif.params.diagnostics;

		assert.match('textDocument/publishDiagnostics', notif.method);
		// Should include at least a warning for 'ghost' (undefined) and one for 'x' (unused)
		let ghostDiag = null;
		for (let d in diags) if (index(d.message, 'ghost') >= 0) { ghostDiag = d; break; }
		assert.match(true, ghostDiag !== null);
		assert.match(2, ghostDiag.severity);  // WARNING
	});

	it('warns for an unused variable with severity WARNING (2)', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let neverUsed = 42;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		assert.match(1, length(notif.params.diagnostics));
		assert.match(2, notif.params.diagnostics[0].severity);  // WARNING
		assert.match(true, index(notif.params.diagnostics[0].message, 'neverUsed') >= 0);
	});

	it('reports error when a named import does not exist in the module', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { noSuchExport } from 'tree_sitter';\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		// Expect at least one ERROR about the missing export.
		// (An unused-import WARNING for 'noSuchExport' may also be present.)
		let errDiags = filter(notif.params.diagnostics, (d) =>
			d.severity === 1 && index(d.message, 'noSuchExport') >= 0);
		assert.match(true, length(errDiags) >= 1);
	});

	it('hints for == with severity 4 (Hint)', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 1;\nlet y = x == 1;\ny;\n" },
		}});

		let notif = lsp.receiveNotification(proc);
		let diags = notif.params.diagnostics;

		assert.match('textDocument/publishDiagnostics', notif.method);
		let eqDiag = null;
		for (let d in diags) if (index(d.message, '===') >= 0) { eqDiag = d; break; }
		assert.match(true, eqDiag !== null);
		assert.match(4, eqDiag.severity);
	});

	it('reports syntax error for malformed code', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = ;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		assert.match(true, length(notif.params.diagnostics) > 0);
		assert.match(1, notif.params.diagnostics[0].severity);
	});

	it('reports not-a-function for @param {string} annotated param when called', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "/**\n * @param {string} name\n */\nfunction greet(name) { name(); }\ngreet('x');\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let diags = filter(notif.params.diagnostics, (d) => index(d.message, 'not a function') >= 0);
		assert.match(true, length(diags) >= 1);
		assert.match(1, diags[0].severity);
	});

	it('reports error when calling a string variable', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = 'hello';\nx();\nx;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let diags = filter(notif.params.diagnostics, (d) => index(d.message, 'not a function') >= 0);
		assert.match(true, length(diags) >= 1);
		assert.match(1, diags[0].severity);
	});

	it('reports error for member access on a null variable', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = null;\nlet y = x.foo;\ny;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let diags = filter(notif.params.diagnostics, (d) => index(d.message, 'may be null') >= 0);
		assert.match(true, length(diags) >= 1);
		assert.match(1, diags[0].severity);
	});

	it('suppresses null member access warning inside if (x) { } guard body', () => {
		// x.foo is only reached when x is non-null; no warning expected.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = null;\nif (x) {\n  let y = x.foo;\n  y;\n}\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let nullDiags = filter(notif.params.diagnostics, (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(nullDiags));
	});

	it('suppresses null warning after if (!x) return guard clause', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let x = null;\nif (!x) return;\nlet y = x.foo;\ny;\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let nullDiags = filter(notif.params.diagnostics, (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(nullDiags));
	});

	it('reports deprecated hint for use of @deprecated imported symbol', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { oldFn } from 'fixtures.deprecated';\noldFn();\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let depDiags = filter(notif.params.diagnostics, (d) => d.message === 'Deprecated');
		assert.match(true, length(depDiags) >= 1);
		assert.match(4, depDiags[0].severity);  // HINT
		assert.match(true, index(depDiags[0].tags, 2) >= 0);  // TAG_DEPRECATED
	});

	it('does not report deprecated hint for non-deprecated imported symbol', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { newFn } from 'fixtures.deprecated';\nnewFn();\n" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		let depDiags = filter(notif.params.diagnostics, (d) => d.message === 'Deprecated');
		assert.match(0, length(depDiags));
	});

	it('re-sends diagnostics on didChange', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.receiveNotification(proc);  // consume the didOpen notification

		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
			textDocument: { uri: 'file:///t.uc', version: 2 },
			contentChanges: [{ text: "import { foo } from 'bad_module';" }],
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		// Expect at least one diagnostic (bad import error; unused-import warning may also appear).
		assert.match(true, length(notif.params.diagnostics) >= 1);
	});
});
