import { describe, it, assert, setup, teardown, contains, not } from 'utest';
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

// Open the marked text and ask for signature help at $0.
function signatureAt(marked) {
	let src = cursors(marked);
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/signatureHelp', params: {
		textDocument: { uri: 'file:///t.uc' },
		position: src.at[0],
	}});
	return lsp.receive(proc);
}

describe('textDocument/signatureHelp', () => {

	it('returns signature when cursor is inside a known function call', () => {
		let resp = signatureAt("let f = (a, b) => a;\nf($01, 2);\n");  // inside f(...)

		assert.match(1, resp.id);
		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(contains('f'), resp.result.signatures[0].label);
	});

	it('returns null when cursor is not inside a call', () => {
		let resp = signatureAt("let $0x = 1;");

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('returns null when cursor is before the opening paren', () => {
		// Cursor on the function name itself — not inside the arguments node.
		let resp = signatureAt("let f = (a, b) => a;\n$0f(1, 2);\n");  // on 'f', before '('

		assert.match(null, resp.result);
	});

	it('returns signature for a namespace-import member call (p.parse)', () => {
		// The callee is a member_expression — most common real-world pattern.
		let resp = signatureAt("import * as p from 'parser';\np.parse($0q, s);\n");  // on 'q', first arg

		assert.match(true, resp.result !== null);
		assert.match(1, length(resp.result.signatures));
		assert.match(contains('parse'), resp.result.signatures[0].label);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a named import call (parse)', () => {
		let resp = signatureAt("import { parse } from 'parser';\nparse($0q, s);\n");  // on 'q', first arg

		assert.match(true, resp.result !== null);
		assert.match(contains('parse'), resp.result.signatures[0].label);
		assert.match(0, resp.result.activeParameter);
	});

	it('returns signature for a stdlib builtin call (push)', () => {
		// push(arr, values) — declared in stdlib.d.uc, always in scope.
		let resp = signatureAt("push([1], $02);\n");  // on '2', second arg

		assert.match(true, resp.result !== null);
		assert.match(contains('push'), resp.result.signatures[0].label);
		assert.match(1, resp.result.activeParameter);
	});

	it('shows innermost call signature when calls are nested', () => {
		// f(g(1), 2) — cursor inside g() shows g's signature, not f's.
		let resp = signatureAt("let f = (a, b) => a;\nlet g = (x) => x;\nf(g($01), 2);\n");  // on '1' inside g(...)

		assert.match(true, resp.result !== null);
		assert.match(contains('g'), resp.result.signatures[0].label);
		assert.match(not(contains('f(')), resp.result.signatures[0].label);
	});

	it('shows outer call signature when cursor is on outer argument', () => {
		// f(g(1), 2) — cursor on '2' shows f's signature, not g's.
		let resp = signatureAt("let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), $02);\n");  // on '2', second arg of f

		assert.match(true, resp.result !== null);
		assert.match(contains('f'), resp.result.signatures[0].label);
		assert.match(1, resp.result.activeParameter);
	});

	it('clamps activeParameter to last param when excess arguments are supplied', () => {
		// f has 2 params; calling with 3 args — activeParameter must not exceed 1.
		let resp = signatureAt("let f = (a, b) => a;\nf(1, 2, $03);\n");  // on '3', third arg

		assert.match(true, resp.result !== null);
		assert.match(1, resp.result.activeParameter);  // clamped from 2 to 1
	});
});
