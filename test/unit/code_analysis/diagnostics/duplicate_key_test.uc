import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { duplicateObjectKey } from 'ucode_analyzer.code_analysis.diagnostics.duplicate_key';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The warnings for a marked snippet: one per name, on the marker pairs
// ($0,$1), ($2,$3), … in order.
function check(marked, ...names) {
	let src = cursors(marked), want = [];
	for (let i = 0; i < length(names); i++)
		push(want, {
			range: { start: src.at[2 * i], end: src.at[2 * i + 1] }, severity: 2, source: 'ucode-analyzer',
			code: 'duplicate-key', message: sprintf("Duplicate key '%s' in object literal", names[i]),
		});
	return { want, got: duplicateObjectKey(open(src.text)) };
}

describe('diagnostics — duplicate object keys', () => {
	it('returns empty list for an object with unique keys', () => {
		assert.match(0, length(duplicateObjectKey(open("let o = { a: 1, b: 2 };\n"))));
	});

	it('warns for a duplicate unquoted key, on its second occurrence', () => {
		let r = check("let o = { a: 1, $0a$1: 2 };\n", 'a');
		assert.match(r.want, r.got);  // a WARNING
	});

	it('warns for a duplicate quoted key', () => {
		let r = check("let o = { \"x\": 1, $0\"x\"$1: 2 };\n", 'x');
		assert.match(r.want, r.got);
	});

	it('does not warn for mixed quoted and unquoted keys with different names', () => {
		assert.match(0, length(duplicateObjectKey(open("let o = { a: 1, \"b\": 2 };\n"))));
	});

	it('reports each duplicate key separately', () => {
		let r = check("let o = { a: 1, b: 2, $0a$1: 3, $2b$3: 4 };\n", 'a', 'b');
		assert.match(r.want, r.got);
	});

	it('does not warn for computed keys', () => {
		let text = "let k = 'a';\nlet o = { [k]: 1, [k]: 2 };\n";
		assert.match(0, length(duplicateObjectKey(open(text))));
	});

	it('detects duplicates in nested objects independently', () => {
		// Outer unique, inner has duplicate
		let r = check("let o = { a: 1, b: { x: 1, $0x$1: 2 } };\n", 'x');
		assert.match(r.want, r.got);
	});

	it('detects a shorthand key duplicated', () => {
		let r = check("let foo = 1;\nlet o = { foo, $0foo$1 };\n", 'foo');
		assert.match(r.want, r.got);
	});

	it('detects a shorthand colliding with an explicit pair', () => {
		let r = check("let foo = 1;\nlet o = { foo, $0foo$1: 3 };\n", 'foo');
		assert.match(r.want, r.got);
	});

	it('detects a shorthand colliding with a string key of the same name', () => {
		let r = check("let a = 1;\nlet o = { a, $0'a'$1: 2 };\n", 'a');
		assert.match(r.want, r.got);
	});

	it('no warning for distinct shorthand keys', () => {
		let text = "let foo = 1, bar = 2;\nlet o = { foo, bar };\n";
		assert.match(0, length(duplicateObjectKey(open(text))));
	});
});
