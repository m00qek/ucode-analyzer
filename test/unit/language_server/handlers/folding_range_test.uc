import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { foldingRanges } from 'language_server.handlers.folding_range';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('foldingRanges — statement blocks', () => {
	it('returns a range for a multi-line function body', () => {
		let doc = open("function foo() {\n  let x = 1;\n}\n");
		let ranges = foldingRanges(doc);
		assert.match(true, length(ranges) >= 1);
		let r = filter(ranges, (r) => r.startLine === 0)[0];
		assert.match(true, r !== null);
		assert.match(2, r.endLine);
	});

	it('does not emit a range for a single-line block', () => {
		let doc = open("function foo() { return 1; }\n");
		let ranges = foldingRanges(doc);
		// All ranges must span more than one line.
		for (let r in ranges)
			assert.match(true, r.endLine > r.startLine);
	});

	it('emits separate ranges for nested blocks', () => {
		let doc = open("function outer() {\n  function inner() {\n    return 1;\n  }\n}\n");
		let ranges = foldingRanges(doc);
		// Both outer (lines 0-4) and inner (lines 1-3) should be foldable.
		assert.match(true, length(ranges) >= 2);
		let starts = sort(map(ranges, (r) => r.startLine));
		assert.match(0, starts[0]);
		assert.match(1, starts[1]);
	});

	it('emits a range for an if-statement block', () => {
		let doc = open("if (true) {\n  let x = 1;\n  let y = 2;\n}\n");
		let ranges = foldingRanges(doc);
		assert.match(true, length(ranges) >= 1);
		assert.match(0, ranges[0].startLine);
		assert.match(3, ranges[0].endLine);
	});

	it('emits a range for a for-loop body', () => {
		let doc = open("for (let i = 0; i < 3; i++) {\n  let x = i;\n}\n");
		let ranges = foldingRanges(doc);
		assert.match(true, length(ranges) >= 1);
	});
});

describe('foldingRanges — import block', () => {
	it('emits an imports range for multiple consecutive import statements', () => {
		let doc = open("import * as a from 'a';\nimport * as b from 'b';\nimport * as c from 'c';\n\nlet x = 1;\n");
		let ranges = foldingRanges(doc);
		let imp = filter(ranges, (r) => r.kind === 'imports')[0];
		assert.match(true, imp !== null);
		assert.match(0, imp.startLine);
		assert.match(2, imp.endLine);
	});

	it('does not emit an imports range for a single import', () => {
		let doc = open("import * as a from 'a';\nlet x = 1;\n");
		let ranges = foldingRanges(doc);
		let imp = filter(ranges, (r) => r.kind === 'imports')[0];
		assert.match(true, imp === null || imp === undefined);
	});

	it('returns empty list for an empty file', () => {
		let doc = open("");
		assert.match(0, length(foldingRanges(doc)));
	});
});
