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
		assert.match(1, length(notif.params.diagnostics));
		assert.match(1, notif.params.diagnostics[0].severity);  // ERROR
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
		assert.match(1, length(notif.params.diagnostics));
		assert.match(1, notif.params.diagnostics[0].severity);
		assert.match(true, index(notif.params.diagnostics[0].message, 'noSuchExport') >= 0);
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
		assert.match(1, length(notif.params.diagnostics));
	});
});
