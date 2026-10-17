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

// The signature help for one signature, label, whose parameters are the
// substrings `params` of it (in order), with `active` the active parameter.
function help(label, params, active) {
	let parameters = [], from = 0;
	for (let p in params) {
		let at = index(substr(label, from), p) + from;
		push(parameters, { label: [ at, at + length(p) ] });
		from = at + length(p);
	}
	return { signatures: [ { label, parameters } ], activeSignature: 0, activeParameter: active };
}

// The help for `let f = (a, b) => a;`.
function helpF(active) {
	return help('f(a: ?, b: ?)', [ 'a: ?', 'b: ?' ], active);
}

describe('textDocument/signatureHelp', () => {

	it('returns signature when cursor is inside a known function call', () => {
		let resp = signatureAt("let f = (a, b) => a;\nf($01, 2);\n");  // inside f(...)

		assert.match(1, resp.id);
		assert.match(helpF(0), resp.result);
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

		assert.match(help('p.parse(parser: object, source: string): object',
			[ 'parser: object', 'source: string' ], 0), resp.result);
	});

	it('returns signature for a named import call (parse)', () => {
		let resp = signatureAt("import { parse } from 'parser';\nparse($0q, s);\n");  // on 'q', first arg

		assert.match(help('parse(parser: object, source: string): object',
			[ 'parser: object', 'source: string' ], 0), resp.result);
	});

	it('returns signature for a stdlib builtin call (push)', () => {
		// push(arr, values) — declared in stdlib.d.uc, always in scope.
		let resp = signatureAt("push([1], $02);\n");  // on '2', second arg

		// T is bound from the arguments.
		assert.match(help('push(arr: list<int>, values: int): ?int',
			[ 'arr: list<int>', 'values: int' ], 1), resp.result);
	});

	it('shows innermost call signature when calls are nested', () => {
		// f(g(1), 2) — cursor inside g() shows g's signature, not f's.
		let resp = signatureAt("let f = (a, b) => a;\nlet g = (x) => x;\nf(g($01), 2);\n");  // on '1' inside g(...)

		assert.match(help('g(x: ?)', [ 'x: ?' ], 0), resp.result);
	});

	it('shows outer call signature when cursor is on outer argument', () => {
		// f(g(1), 2) — cursor on '2' shows f's signature, not g's.
		let resp = signatureAt("let f = (a, b) => a;\nlet g = (x) => x;\nf(g(1), $02);\n");  // on '2', second arg of f

		assert.match(helpF(1), resp.result);
	});

	it('clamps activeParameter to last param when excess arguments are supplied', () => {
		// f has 2 params; calling with 3 args — activeParameter must not exceed 1.
		let resp = signatureAt("let f = (a, b) => a;\nf(1, 2, $03);\n");  // on '3', third arg

		assert.match(helpF(1), resp.result);  // clamped from 2 to 1
	});
});
