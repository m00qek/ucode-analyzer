import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { selectionRanges } from 'ucode_analyzer.language_server.handlers.selection_range';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The selection ranges at $0 of the text of `src` (from cursors()).
function rangesAt(src) {
	return selectionRanges(open(src.text), [src.at[0]]);
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
		let src = cursors("let $0x = $11;\n");
		let result = selectionRanges(open(src.text), [ src.at[0], src.at[1] ]);
		assert.match(2, length(result));
	});

	it('innermost range covers the leaf node', () => {
		let src = cursors("let $0$1x$2 = 1;\n");
		let result = rangesAt(src);
		assert.match(true, result !== null);
		assert.match({ start: src.at[1], end: src.at[2] }, result[0].range);
	});

	it('parent chain expands outward', () => {
		let result = rangesAt(cursors("let x = $01;\n"));
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
		let result = rangesAt(cursors("let $0x = 1;\n"));
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
		let src = cursors("$1let $0x = 1;\n");
		let result = rangesAt(src);
		let chain = flattenChain(result[0]);
		let outer = chain[length(chain) - 1];
		assert.match(src.at[1], outer.start);
	});

	it('cursor inside a function body expands to function, then program', () => {
		// on 'a' inside the return statement
		let result = rangesAt(cursors("function f(a, b) {\n  return $0a + b;\n}\n"));
		let chain = flattenChain(result[0]);
		// Should have at least: identifier, binary_expression, return_statement,
		//   statement_block, function_declaration, program.
		assert.match(true, length(chain) >= 4);
	});

	it('handles multiple positions independently', () => {
		let src = cursors("let $0$2a$3 = 1;\nlet $1$4b$5 = 2;\n");
		let result = selectionRanges(open(src.text), [ src.at[0], src.at[1] ]);
		assert.match(2, length(result));
		// Each entry is independent: its innermost range is its own identifier.
		assert.match({ start: src.at[2], end: src.at[3] }, result[0].range);
		assert.match({ start: src.at[4], end: src.at[5] }, result[1].range);
	});
});
