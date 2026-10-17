import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { preferStrictEquality } from 'ucode_analyzer.code_analysis.diagnostics.prefer_strict_equality';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('diagnostics — prefer strict equality', () => {
	it('returns empty list when no == or != is used', () => {
		documents.open(URI, "let x = 1;\nlet y = x === 1;\n", 1);

		assert.match(0, length(preferStrictEquality(documents.get(URI))));
	});

	it('hints for == with severity 4', () => {
		documents.open(URI, "let x = 1 == 1;\n", 1);

		let diags = preferStrictEquality(documents.get(URI));

		assert.match(1, length(diags));
		assert.match(4, diags[0].severity);
	});

	it('message suggests === when operator is ==', () => {
		documents.open(URI, "let x = 1 == 2;\n", 1);

		let d = preferStrictEquality(documents.get(URI))[0];

		assert.match(contains('==='), d.message);
		assert.match(contains('=='), d.message);
	});

	it('hints for != and suggests !==', () => {
		documents.open(URI, "let x = 1 != 2;\n", 1);

		let d = preferStrictEquality(documents.get(URI))[0];

		assert.match(contains('!=='), d.message);
	});

	it('does not flag === or !==', () => {
		documents.open(URI, "let a = 1 === 1;\nlet b = 1 !== 2;\n", 1);

		assert.match(0, length(preferStrictEquality(documents.get(URI))));
	});

	it('range covers only the operator token', () => {
		documents.open(URI, "let x = 1 == 2;\n", 1);

		let r = preferStrictEquality(documents.get(URI))[0].range;

		// '==' starts at column 10
		assert.match(0, r.start.line);
		assert.match(10, r.start.character);
		assert.match(0, r.end.line);
		assert.match(12, r.end.character);
	});

	it('reports one hint per operator', () => {
		documents.open(URI, "let a = 1 == 2;\nlet b = 3 != 4;\n", 1);

		assert.match(2, length(preferStrictEquality(documents.get(URI))));
	});

	it('finds == nested inside a function body', () => {
		documents.open(URI, "function f(x) { return x == null; }\n", 1);

		assert.match(1, length(preferStrictEquality(documents.get(URI))));
	});
});
