import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as lsp from 'lsp_client';

const DOC = {
	uri: 'file:///test.uc',
	languageId: 'ucode',
	version: 1,
	text: 'let x = 5;',
};

// Standalone: needs to inspect the initialize response itself.
describe('initialize response', () => {
	it('returns capabilities and serverInfo', () => {
		let proc = lsp.connect();
		let resp = lsp.initialize(proc);
		let caps = resp.result.capabilities;

		assert.match(true, type(caps) === 'object');
		assert.match(1,    caps.textDocumentSync);
		assert.match(true, caps.hoverProvider);
		assert.match(true, caps.definitionProvider);
		assert.match(true, caps.referencesProvider);
		assert.match(true, caps.documentSymbolProvider);
		assert.match(true, caps.renameProvider);
		assert.match(true, type(caps.completionProvider)    === 'object');
		assert.match(true, type(caps.signatureHelpProvider) === 'object');
		assert.match('ucode-language-server', resp.result.serverInfo.name);

		let shutdownResp = lsp.shutdown(proc);
		assert.match(null, shutdownResp.result);
		assert.match(0, lsp.close(proc));
	});
});

describe('LSP document sync', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('textDocument/hover returns inferred type for a variable', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0', id: 1,
			method: 'textDocument/hover',
			params: {
				textDocument: { uri: DOC.uri },
				position: { line: 0, character: 4 },  // cursor on 'x' in 'let x = 5;'
			},
		});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match('markdown', resp.result.contents.kind);
		assert.match(true, index(resp.result.contents.value, 'int') >= 0);
	});

	it('textDocument/hover returns null for unopened document', () => {
		lsp.send(proc, {
			jsonrpc: '2.0', id: 1,
			method: 'textDocument/hover',
			params: {
				textDocument: { uri: 'file:///not-open.uc' },
				position: { line: 0, character: 0 },
			},
		});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('unknown request returns MethodNotFound', () => {
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(-32601, resp.error.code);
	});

	it('textDocument/didOpen is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});

	it('textDocument/didChange is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0',
			method: 'textDocument/didChange',
			params: {
				textDocument: { uri: DOC.uri, version: 2 },
				contentChanges: [{ text: 'let x = 99;' }],
			},
		});

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});

	it('textDocument/didClose is accepted', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: DOC } });
		lsp.send(proc, {
			jsonrpc: '2.0',
			method: 'textDocument/didClose',
			params: { textDocument: { uri: DOC.uri } },
		});

		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'unknown/method', params: null });
		assert.match(1, lsp.receive(proc).id);
	});
});

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
		// parse is at line 80 col 16 in tree_sitter.uc (after 'export function ')
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
		assert.match(80, resp.result.range.start.line);
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
		assert.match(80, resp.result.range.start.line);
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
});

describe('textDocument/completion', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('includes declared local variable in results', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let answer = 42;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // after the declaration
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'answer') >= 0);
	});

	it('reflects new declaration added by didChange', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didChange', params: {
			textDocument: { uri: 'file:///t.uc', version: 2 },
			contentChanges: [{ text: "let x = 1;\nlet y = 2;\n" }],
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },  // after both declarations
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'x') >= 0);
		assert.match(true, index(labels, 'y') >= 0);
	});

	it('namespace import: ts. offers only tree_sitter exports', () => {
		// Cursor right after the dot — trigger-character path.
		let text = "import * as ts from 'tree_sitter';\nlet x = 5;\nts.\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 3 },  // after 'ts.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'parse') >= 0);     // ts export
		assert.match(false, index(labels, 'x') >= 0);        // local — must NOT appear
	});

	it('namespace import: ts.pa offers only tree_sitter exports', () => {
		// Cursor on a partially-typed property — member_expression primary path.
		let text = "import * as ts from 'tree_sitter';\nts.pa\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 4 },  // on 'a' of 'ts.pa'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(true, index(labels, 'parse') >= 0);
	});

	it('named import record: assert. offers only assert members', () => {
		// assert is imported as a named import whose type is a record.
		let text = "import { assert } from 'utest';\nlet y = 1;\nassert.\n";
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/completion', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 7 },  // after 'assert.'
		}});

		let resp = lsp.receive(proc);
		let labels = map(resp.result, (i) => i.label);

		assert.match(1, resp.id);
		assert.match(true, index(labels, 'match') >= 0);     // assert member
		assert.match(true, index(labels, 'throws') >= 0);    // assert member
		assert.match(false, index(labels, 'y') >= 0);        // local — must NOT appear
	});
});

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
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});

		let notif = lsp.receiveNotification(proc);

		assert.match('textDocument/publishDiagnostics', notif.method);
		assert.match(0, length(notif.params.diagnostics));
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

describe('textDocument/signatureHelp', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns signature when cursor is inside a known function call', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 2 },  // inside f(...)
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(true, index(resp.result.signatures[0].label, 'f') >= 0);
	});

	it('returns null when cursor is not inside a call', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('returns null when cursor is before the opening paren', () => {
		// Cursor on the function name itself — not inside the arguments node.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 0 },  // on 'f', before '('
		}});

		let resp = lsp.receive(proc);

		assert.match(null, resp.result);
	});

	it('returns signature for a namespace-import member call (ts.parse)', () => {
		// The callee is a member_expression — most common real-world pattern.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import * as ts from 'tree_sitter';\nts.parse(p, s);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 9 },  // on 'p', first arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(true, index(resp.result.signatures[0].label, 'parse') >= 0);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a named import call (parse)', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "import { parse } from 'tree_sitter';\nparse(p, s);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 6 },  // on 'p', first arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'parse') >= 0);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a stdlib builtin call (push)', () => {
		// push(arr, values) — declared in stdlib.d.uc, always in scope.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "push([1], 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 10 },  // on '2', second arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'push') >= 0);
		assert.match(1, resp.result.activeParameter);
	});

	it('shows innermost call signature when calls are nested', () => {
		// f(g(1), 2) — cursor inside g() shows g's signature, not f's.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 4 },  // on '1' inside g(...)
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'g') >= 0);
		assert.match(false, index(resp.result.signatures[0].label, 'f(') >= 0);
	});

	it('shows outer call signature when cursor is on outer argument', () => {
		// f(g(1), 2) — cursor on '2' shows f's signature, not g's.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), 2);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 8 },  // on '2', second arg of f
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(true, index(resp.result.signatures[0].label, 'f') >= 0);
		assert.match(1, resp.result.activeParameter);
	});

	it('clamps activeParameter to last param when excess arguments are supplied', () => {
		// f has 2 params; calling with 3 args — activeParameter must not exceed 1.
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let f = (a, b) => a;\nf(1, 2, 3);\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 1, character: 8 },  // on '3', third arg
		}});

		let resp = lsp.receive(proc);

		assert.match(true, resp.result !== null);
		assert.match(1, resp.result.activeParameter);  // clamped from 2 to 1
	});
});

describe('textDocument/references', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns all occurrences of an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let z = 0;\nz;\nz;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/references', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 4 },  // on 'z' declaration
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(3, length(resp.result));  // declaration + 2 uses
		for (let loc in resp.result)
			assert.match('file:///t.uc', loc.uri);
	});

	it('returns null when cursor is not on an identifier', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/references', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },  // 'l' in 'let'
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});
});

describe('textDocument/documentSymbol', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns symbols for all top-level declarations', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\nfunction greet() {}\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);
		let names = sort(map(resp.result, (s) => s.name));

		assert.match(1, resp.id);
		assert.match(2, length(resp.result));
		assert.match('count', names[0]);
		assert.match('greet', names[1]);
	});

	it('returns empty list for a file with no declarations', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/documentSymbol', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});
});

describe('textDocument/rename', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('returns workspace edit replacing all occurrences', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let count = 0;\ncount;\n" },
		}});
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
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: "let x = 1;" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/rename', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 0, character: 0 },
			newName: 'y',
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});
});

describe('template type parameter propagation', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('slice of int array yields ?list<int>', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let xs = [1, 2, 3];\nlet r = slice(xs, 1);\nr;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },  // 'r' in standalone r;
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'list<int>') >= 0);
	});

	it('slice of string array from split yields ?list<string>', () => {
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1,
				text: "let parts = split(\"a,b,c\", \",\");\nlet r = slice(parts, 1);\nr;\n" },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 2, character: 0 },
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'list<string>') >= 0);
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
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: src },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 5, character: 4 },  // 'r' after 4 spaces
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'list<K>') >= 0);
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
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri: 'file:///t.uc', languageId: 'ucode', version: 1, text: src },
		}});
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri: 'file:///t.uc' },
			position: { line: 5, character: 4 },  // 'r' after 4 spaces
		}});

		let resp = lsp.receive(proc);

		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'list<K>') >= 0);
	});
});

describe('export function visible to later code in same file', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('calling a sibling export function resolves to its return type', () => {
		let src = "/**\n * @returns {string}\n */\nexport function tag(x) { return '' + x; }\nexport function caller(v) {\n    let r = tag(v);\n    r;\n}\n";
		let uri = 'file:///export_fn_scope.uc';
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri, languageId: 'ucode', version: 1, text: src },
		}});
		// 'r' on the standalone 'r;' line — line 6 (0-based), character 4
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 6, character: 4 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'string') >= 0);
	});
});

describe('nested block scope — let inside for-in body', () => {
	let proc;

	beforeEach(() => {
		proc = lsp.connect();
		lsp.initialize(proc);
	});

	afterEach(() => {
		lsp.shutdown(proc);
		assert.match(0, lsp.close(proc));
	});

	it('let declared inside a for-in body resolves to its initializer type', () => {
		let src = "/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let item in items) {\n    let k = tag(item);\n    k;\n}\n";
		let uri = 'file:///nested_scope.uc';
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri, languageId: 'ucode', version: 1, text: src },
		}});
		// 'k' on the standalone 'k;' line — line 6 (0-based), character 4
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 6, character: 4 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'string') >= 0);
	});

	it('let declared inside a doubly-nested for-in body resolves correctly', () => {
		let src = "/**\n * @returns {string}\n */\nfunction tag(x) { return '' + x; }\nfor (let outer in items) {\n    for (let inner in outer) {\n        let k = tag(inner);\n        k;\n    }\n}\n";
		let uri = 'file:///double_nested.uc';
		lsp.send(proc, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
			textDocument: { uri, languageId: 'ucode', version: 1, text: src },
		}});
		// 'k' on the standalone 'k;' line — line 7 (0-based), character 8
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/hover', params: {
			textDocument: { uri },
			position: { line: 7, character: 8 },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(true, index(resp.result.contents.value, 'string') >= 0);
	});
});

// Standalone: afterEach shutdown would conflict with the server already having exited.
describe('exit behavior', () => {
	it('exit without shutdown returns non-zero', () => {
		let proc = lsp.connect();
		lsp.initialize(proc);

		lsp.send(proc, { jsonrpc: '2.0', method: 'exit', params: {} });
		assert.match(true, lsp.close(proc) !== 0);
	});
});
