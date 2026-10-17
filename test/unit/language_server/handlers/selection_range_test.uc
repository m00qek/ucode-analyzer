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

// The range from marker a to marker b.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
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
		let src = cursors("$6let $2$0x$3 = $4$11$5;$7\n$8");
		let result = selectionRanges(open(src.text), [ src.at[0], src.at[1] ]);
		// the declarator, the statement and the program are shared
		let tail = [ span(src, 2, 5), span(src, 6, 7), span(src, 6, 8) ];
		assert.match([ [ span(src, 2, 3), ...tail ], [ span(src, 4, 5), ...tail ] ], map(result, flattenChain));
	});

	it('innermost range covers the leaf node', () => {
		let src = cursors("let $0$1x$2 = 1;\n");
		let result = rangesAt(src);
		assert.match(1, length(result));
		assert.match({ start: src.at[1], end: src.at[2] }, result[0].range);
	});

	it('parent chain expands outward', () => {
		let src = cursors("$5let $3x = $0$11$2$4;$6\n$7");
		let chain = flattenChain(rangesAt(src)[0]);
		// '1', the declarator, the statement, the program
		assert.match([ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6), span(src, 5, 7) ], chain);
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
		let src = cursors("$1let $0x = 1;\n$2");
		let result = rangesAt(src);
		let chain = flattenChain(result[0]);
		assert.match(span(src, 1, 2), chain[length(chain) - 1]);
	});

	it('cursor inside a function body expands to function, then program', () => {
		// on 'a' inside the return statement
		let src = cursors("$7function f(a, b) $5{\n  $3return $0a$2 + b$4;$1\n}$6$8\n$9");
		let chain = flattenChain(rangesAt(src)[0]);
		// identifier, binary_expression, return_statement, statement_block,
		// function_declaration, program
		assert.match([
			span(src, 0, 2), span(src, 0, 4), span(src, 3, 1),
			span(src, 5, 6), span(src, 7, 8), span(src, 7, 9),
		], chain);
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
