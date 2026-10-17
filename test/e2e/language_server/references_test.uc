import { describe, it, assert, setup, teardown, contains, not, any_order } from 'utest';
import * as lsp from 'client';
import { cursors, locate } from 'cursor';
import * as fixture from 'fixture';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Ask for the references at position in uri.
function referencesAt(id, uri, position, context) {
	let params = { textDocument: { uri }, position };
	if (context) params.context = context;
	lsp.send(proc, { jsonrpc: '2.0', id, method: 'textDocument/references', params });
	return lsp.receive(proc);
}

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

// The range of `name` at pos.
function rangeAt(pos, name) {
	return { start: pos, end: { line: pos.line, character: pos.character + length(name) } };
}

describe('textDocument/references', () => {

	it('returns all occurrences of an identifier', () => {
		let src = cursors("let $0$1z$2 = 0;\n$3z$4;\n$5z$6;\n");  // on the 'z' declaration
		lsp.open(proc, 'file:///t.uc', src.text);

		let resp = referencesAt(1, 'file:///t.uc', src.at[0]);

		assert.match(1, resp.id);
		assert.match(any_order([  // declaration + 2 uses
			{ uri: 'file:///t.uc', range: span(src, 1, 2) },
			{ uri: 'file:///t.uc', range: span(src, 3, 4) },
			{ uri: 'file:///t.uc', range: span(src, 5, 6) },
		]), resp.result);
	});

	it('returns null when cursor is not on an identifier', () => {
		let src = cursors("$0let x = 1;");
		lsp.open(proc, 'file:///t.uc', src.text);

		let resp = referencesAt(1, 'file:///t.uc', src.at[0]);

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('does not include same-named identifiers from a different scope', () => {
		// Each function has a parameter `x`; references on one must not include the other.
		let src = cursors("function a($0$1x$2) { return $3x$4; }\nfunction b(x) { return x; }\n");
		lsp.open(proc, 'file:///t.uc', src.text);

		let resp = referencesAt(2, 'file:///t.uc', src.at[0]);

		assert.match(2, resp.id);
		// Only the declaration + use inside a; function b's x is excluded.
		assert.match(any_order([
			{ uri: 'file:///t.uc', range: span(src, 1, 2) },
			{ uri: 'file:///t.uc', range: span(src, 3, 4) },
		]), resp.result);
	});

	it('cross-file: finds references in the declaring module when cursor is on import', () => {
		// Open a file that imports `parse` from parser.uc (which exists on disk).
		let uri = 'file:///t_xref.uc';
		let src = cursors("import { $1parse$2 } from 'parser';\n$0$3parse$4();\n");
		lsp.open(proc, uri, src.text);

		let resp = referencesAt(3, uri, src.at[0]);
		let locs = resp.result;

		assert.match(3, resp.id);
		assert.match(true, type(locs) === 'array');

		// In parser.uc: the declaration and the call in parseString().
		let parser = fixture.read('parser.uc');
		let decl = rangeAt(locate(parser, 'export function parse(', 0, length('export function ')), 'parse');
		let call = rangeAt(locate(parser, 'return parse(', 0, length('return ')), 'parse');
		assert.match(any_order([ decl, call ]),
			map(filter(locs, (l) => l.uri === fixture.uri('parser.uc')), (l) => l.range));

		// And in the importing file itself: the import specifier and the call.
		assert.match(any_order([ span(src, 1, 2), span(src, 3, 4) ]),
			map(filter(locs, (l) => l.uri === uri), (l) => l.range));
	});

	it('cross-file: includeDeclaration:false excludes the export declaration', () => {
		let fixUri = fixture.uri('greet.uc');
		let greet = cursors("function $1greet$2() {}\nexport { greet };\n");
		lsp.open(proc, fixUri, greet.text);
		let uri = fixture.uri('ref_caller.uc');
		let src = cursors("import { greet } from 'greet';\n$0greet();\n");
		lsp.open(proc, uri, src.text);

		// The declaration is `function greet` in the fixture.
		let decl = { uri: fixUri, range: span(greet, 1, 2) };

		// includeDeclaration:true → the declaration is present.
		let withDecl = referencesAt(4, uri, src.at[0], { includeDeclaration: true });
		assert.match(4, withDecl.id);
		assert.match(contains([ decl ]), withDecl.result);

		// includeDeclaration:false → the declaration is dropped.
		let noDecl = referencesAt(5, uri, src.at[0], { includeDeclaration: false });
		assert.match(5, noDecl.id);
		assert.match(true, type(noDecl.result) === 'array');
		assert.match(not(contains([ decl ])), noDecl.result);
	});
});
