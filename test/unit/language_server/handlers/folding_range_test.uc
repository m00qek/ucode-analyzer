import { describe, it, assert, afterEach, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { foldingRanges } from 'ucode_analyzer.language_server.handlers.folding_range';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('foldingRanges — statement blocks', () => {
	it('returns a range for a multi-line function body', () => {
		let doc = open("function foo() {\n  let x = 1;\n}\n");
		assert.match([ { startLine: 0, endLine: 2 } ], foldingRanges(doc));
	});

	it('does not emit a range for a single-line block', () => {
		let doc = open("function foo() { return 1; }\n");
		assert.match([], foldingRanges(doc));
	});

	it('emits separate ranges for nested blocks', () => {
		let doc = open("function outer() {\n  function inner() {\n    return 1;\n  }\n}\n");
		// Both outer (lines 0-4) and inner (lines 1-3) should be foldable.
		assert.match(any_order([ { startLine: 0, endLine: 4 }, { startLine: 1, endLine: 3 } ]), foldingRanges(doc));
	});

	it('emits a range for an if-statement block', () => {
		let doc = open("if (true) {\n  let x = 1;\n  let y = 2;\n}\n");
		assert.match([ { startLine: 0, endLine: 3 } ], foldingRanges(doc));
	});

	it('emits a range for a for-loop body', () => {
		let doc = open("for (let i = 0; i < 3; i++) {\n  let x = i;\n}\n");
		assert.match([ { startLine: 0, endLine: 2 } ], foldingRanges(doc));
	});
});

describe('foldingRanges — import block', () => {
	it('emits an imports range for multiple consecutive import statements', () => {
		let doc = open("import * as a from 'a';\nimport * as b from 'b';\nimport * as c from 'c';\n\nlet x = 1;\n");
		assert.match([ { startLine: 0, endLine: 2, kind: 'imports' } ], foldingRanges(doc));
	});

	it('does not emit an imports range for a single import', () => {
		let doc = open("import * as a from 'a';\nlet x = 1;\n");
		assert.match([], foldingRanges(doc));
	});

	it('returns empty list for an empty file', () => {
		let doc = open("");
		assert.match([], foldingRanges(doc));
	});
});
