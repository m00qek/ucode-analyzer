import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { unreachableCode } from 'language_server.handlers.diagnostics.unreachable_code';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('diagnostics — unreachable code', () => {
	it('returns empty list when no dead code exists', () => {
		documents.open(URI, "function f() {\n  let x = 1;\n  return x;\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('flags a statement after return with severity 2', () => {
		documents.open(URI, "function f() {\n  return 1;\n  let x = 2;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);
		assert.match('Unreachable code', diags[0].message);
	});

	it('flags a statement after break', () => {
		documents.open(URI, "for (let i = 0; i < 10; i++) {\n  break;\n  let x = 1;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));
		assert.match('Unreachable code', diags[0].message);
	});

	it('flags a statement after continue', () => {
		documents.open(URI, "for (let i = 0; i < 10; i++) {\n  continue;\n  let x = 1;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));
		assert.match('Unreachable code', diags[0].message);
	});

	it('flags multiple statements after return', () => {
		documents.open(URI, "function f() {\n  return 1;\n  let a = 2;\n  let b = 3;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(2, length(diags));
	});

	it('does not flag the return statement itself', () => {
		documents.open(URI, "function f() {\n  return 1;\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('reports the correct line for unreachable statement', () => {
		documents.open(URI, "function f() {\n  return 1;\n  let x = 2;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));
		assert.match(2, diags[0].range.start.line);  // 0-indexed: line 2 is 'let x = 2'
	});

	it('does not flag code before the return', () => {
		documents.open(URI, "function f() {\n  let x = 1;\n  return x;\n  let y = 2;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));
		assert.match('Unreachable code', diags[0].message);
	});

	it('handles nested functions independently', () => {
		// Dead code in inner function does not affect outer, and vice versa.
		documents.open(URI, "function outer() {\n  function inner() {\n    return 1;\n    let x = 2;\n  }\n  let y = 3;\n}\n", 1);
		let diags = unreachableCode(documents.get(URI));
		assert.match(1, length(diags));  // only 'let x = 2' inside inner
	});

	it('returns empty list for top-level code with no blocks', () => {
		documents.open(URI, "let x = 1;\nlet y = 2;\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});
});
