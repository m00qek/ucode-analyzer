import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { duplicateObjectKey } from 'language_server.handlers.diagnostics.duplicate_object_key';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — duplicate object keys', () => {
	it('returns empty list for an object with unique keys', () => {
		assert.match(0, length(duplicateObjectKey(open("let o = { a: 1, b: 2 };\n"))));
	});

	it('warns for a duplicate unquoted key', () => {
		let diags = duplicateObjectKey(open("let o = { a: 1, a: 2 };\n"));
		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);   // WARNING
		assert.match('duplicate-key', diags[0].code);
		assert.match(true, index(diags[0].message, "'a'") >= 0);
	});

	it('warns for a duplicate quoted key', () => {
		let diags = duplicateObjectKey(open("let o = { \"x\": 1, \"x\": 2 };\n"));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'x'") >= 0);
	});

	it('does not warn for mixed quoted and unquoted keys with different names', () => {
		assert.match(0, length(duplicateObjectKey(open("let o = { a: 1, \"b\": 2 };\n"))));
	});

	it('reports each duplicate key separately', () => {
		let diags = duplicateObjectKey(open("let o = { a: 1, b: 2, a: 3, b: 4 };\n"));
		assert.match(2, length(diags));
	});

	it('does not warn for computed keys', () => {
		let text = "let k = 'a';\nlet o = { [k]: 1, [k]: 2 };\n";
		assert.match(0, length(duplicateObjectKey(open(text))));
	});

	it('reports duplicate key on the second occurrence, not the first', () => {
		let diags = duplicateObjectKey(open("let o = { a: 1, a: 2 };\n"));
		// 'a' second occurrence starts after the first 'a: 1, '
		assert.match(0, diags[0].range.start.line);
		assert.match(true, diags[0].range.start.character > 4);
	});

	it('detects duplicates in nested objects independently', () => {
		// Outer unique, inner has duplicate
		let text = "let o = { a: 1, b: { x: 1, x: 2 } };\n";
		let diags = duplicateObjectKey(open(text));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'x'") >= 0);
	});
});
