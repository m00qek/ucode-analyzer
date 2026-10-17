import { describe, it, assert, setup, teardown } from 'utest';
import * as fs from 'fs';
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

// Open the cursors' text and ask for the definition at $0.
function definitionAt(src) {
	lsp.open(proc, 'file:///t.uc', src.text);
	lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/definition', params: {
		textDocument: { uri: 'file:///t.uc' },
		position: src.at[0],
	}});
	return lsp.receive(proc);
}

// Where `parse` is declared in parser.uc (after 'export function ').
function parseDecl() {
	return locate(fixture.read('parser.uc'), 'export function parse(', 0, length('export function '));
}

describe('textDocument/definition', () => {

	it('returns the location of a local declaration', () => {
		let src = cursors("let $1x = 5;\n$0x;");
		let resp = definitionAt(src);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(src.at[1], resp.result.range.start);
	});

	it('returns null for an unknown identifier', () => {
		let resp = definitionAt(cursors("$0foo;"));

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('returns the location of a local function declaration', () => {
		let src = cursors("function $1greet() {}\n$0greet;");
		let resp = definitionAt(src);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(src.at[1], resp.result.range.start);
	});

	it('returns null for a non-identifier node', () => {
		let resp = definitionAt(cursors("$0let x = 5;"));  // 'let' — anonymous token

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('follows a named import to an inline export function', () => {
		let resp = definitionAt(cursors("import { parse } from 'parser';\n$0parse;\n"));

		assert.match(1, resp.id);
		assert.match(fixture.uri('parser.uc'), resp.result.uri);
		assert.match(parseDecl(), resp.result.range.start);
	});

	it('follows a named import to a function declared via export { name }', () => {
		// greet.uc: function greet() {}  export { greet };
		let resp = definitionAt(cursors("import { greet } from 'greet';\n$0greet;\n"));

		assert.match(1, resp.id);
		assert.match(fixture.uri('greet.uc'), resp.result.uri);
		assert.match(locate(fixture.read('greet.uc'), 'greet'), resp.result.range.start);
	});

	it('returns the location of an inline export let declaration', () => {
		let src = cursors("export let $1count = 0;\n$0count;\n");
		let resp = definitionAt(src);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(src.at[1], resp.result.range.start);
	});

	it('returns the location of an inline export function declaration', () => {
		let src = cursors("export function $1greet() {};\n$0greet;\n");
		let resp = definitionAt(src);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(src.at[1], resp.result.range.start);
	});

	it('jumps to parameter declaration when cursor is on a parameter reference', () => {
		let src = cursors("function parse($1ts, opts) {\n$0ts;\n}");
		let resp = definitionAt(src);

		assert.match(1, resp.id);
		assert.match('file:///t.uc', resp.result.uri);
		assert.match(src.at[1], resp.result.range.start);
	});

	it('jumps to module top when cursor is on a namespace import alias', () => {
		let resp = definitionAt(cursors("import * as p from 'parser';\n$0p;\n"));

		assert.match(1, resp.id);
		assert.match(fixture.uri('parser.uc'), resp.result.uri);
		assert.match({ line: 0, character: 0 }, resp.result.range.start);
	});

	it('jumps to the export when cursor is on a member expression property', () => {
		let resp = definitionAt(cursors("import * as p from 'parser';\np.$0parse;\n"));

		assert.match(1, resp.id);
		assert.match(fixture.uri('parser.uc'), resp.result.uri);
		assert.match(parseDecl(), resp.result.range.start);
	});

	it('returns null for a property not exported by the module', () => {
		let resp = definitionAt(cursors("import * as p from 'parser';\np.$0doesNotExist;\n"));

		assert.match(1, resp.id);
		assert.match(null, resp.result);
	});

	it('follows a renamed import to the original declaration', () => {
		let resp = definitionAt(cursors("import { parse as p } from 'parser';\n$0p;\n"));

		assert.match(1, resp.id);
		assert.match(fixture.uri('parser.uc'), resp.result.uri);
		assert.match(parseDecl(), resp.result.range.start);
	});

	it('jumps to the field definition when cursor is on a member of a named import record', () => {
		// assert is a named import from utest whose type is a record.
		// Cursor on 'match' in 'assert.match' — should jump to 'match' key in assert.uc.
		let resp = definitionAt(cursors("import { assert } from 'utest';\nassert.$0match;\n"));

		let path = '/usr/share/ucode/utest/assert.uc';
		assert.match(1, resp.id);
		assert.match('file://' + path, resp.result.uri);
		assert.match(locate(fs.readfile(path), 'export function match(', 0, length('export function ')),
			resp.result.range.start);
	});
});
