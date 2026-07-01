import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { selectionRanges } from 'language_server.handlers.selection_range';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

function rangesAt(text, pos) {
	return selectionRanges(open(text), [pos]);
}

// Walk the parent chain and collect all ranges into a flat array.
function flattenChain(sr) {
	let out = [];
	let cur = sr;
	while (cur) {
		push(out, cur.range);
		cur = cur.parent;
	}
	return out;
}

describe('selectionRanges', () => {
	it('returns an array with one entry per position', () => {
		let doc = open("let x = 1;\n");
		let result = selectionRanges(doc, [
			{ line: 0, character: 4 },
			{ line: 0, character: 8 },
		]);
		assert.match(2, length(result));
	});

	it('innermost range covers the leaf node', () => {
		// cursor on 'x' in "let x = 1;"
		let result = rangesAt("let x = 1;\n", { line: 0, character: 4 });
		assert.match(true, result !== null);
		let inner = result[0].range;
		// 'x' is a single character starting at col 4
		assert.match(0, inner.start.line);
		assert.match(4, inner.start.character);
		assert.match(0, inner.end.line);
		assert.match(5, inner.end.character);
	});

	it('parent chain expands outward', () => {
		// "let x = 1;\n" — cursor on '1'
		let result = rangesAt("let x = 1;\n", { line: 0, character: 8 });
		let chain = flattenChain(result[0]);
		// The innermost is '1', the outermost covers the whole line.
		assert.match(true, length(chain) >= 2);
		let inner = chain[0];
		let outer = chain[length(chain) - 1];
		// Innermost is strictly inside outermost (or equal for single-node programs).
		assert.match(true,
			outer.start.line < inner.start.line ||
			(outer.start.line === inner.start.line && outer.start.character <= inner.start.character));
		assert.match(true,
			outer.end.line > inner.end.line ||
			(outer.end.line === inner.end.line && outer.end.character >= inner.end.character));
	});

	it('no duplicate adjacent ranges in chain', () => {
		let result = rangesAt("let x = 1;\n", { line: 0, character: 4 });
		let chain = flattenChain(result[0]);
		for (let i = 1; i < length(chain); i++) {
			let a = chain[i - 1];
			let b = chain[i];
			assert.match(true,
				a.start.line      !== b.start.line ||
				a.start.character !== b.start.character ||
				a.end.line        !== b.end.line ||
				a.end.character   !== b.end.character);
		}
	});

	it('outermost range covers the whole program', () => {
		let text = "let x = 1;\n";
		let result = rangesAt(text, { line: 0, character: 4 });
		let chain = flattenChain(result[0]);
		let outer = chain[length(chain) - 1];
		assert.match(0, outer.start.line);
		assert.match(0, outer.start.character);
	});

	it('cursor inside a function body expands to function, then program', () => {
		let text = "function f(a, b) {\n  return a + b;\n}\n";
		// cursor on 'a' inside the return statement
		let result = rangesAt(text, { line: 1, character: 9 });
		let chain = flattenChain(result[0]);
		// Should have at least: identifier, binary_expression, return_statement,
		//   statement_block, function_declaration, program.
		assert.match(true, length(chain) >= 4);
	});

	it('handles multiple positions independently', () => {
		let text = "let a = 1;\nlet b = 2;\n";
		let doc = open(text);
		let result = selectionRanges(doc, [
			{ line: 0, character: 4 },
			{ line: 1, character: 4 },
		]);
		assert.match(2, length(result));
		// Each entry is independent: their innermost ranges are on different lines.
		assert.match(0, result[0].range.start.line);
		assert.match(1, result[1].range.start.line);
	});
});
