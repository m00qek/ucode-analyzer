import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { preferStrictEquality } from 'ucode_analyzer.code_analysis.diagnostics.prefer_strict_equality';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// The hints for a marked snippet: one per loose operator, on the marker pairs
// ($0,$1), ($2,$3), … in order, each suggesting its strict form.
function check(marked) {
	let src = cursors(marked), want = [];
	for (let i = 0; i + 1 < length(src.at); i += 2) {
		let op = substr(src.text, src.offset[i], src.offset[i + 1] - src.offset[i]);
		push(want, {
			range: { start: src.at[i], end: src.at[i + 1] }, severity: 4, source: 'ucode-analyzer',
			code: 'prefer-strict-equality', message: sprintf("Prefer '%s=' over '%s'", op, op),
		});
	}
	documents.open(URI, src.text, 1);
	return { want, got: preferStrictEquality(documents.get(URI)) };
}

describe('diagnostics — prefer strict equality', () => {
	it('returns empty list when no == or != is used', () => {
		documents.open(URI, "let x = 1;\nlet y = x === 1;\n", 1);

		assert.match(0, length(preferStrictEquality(documents.get(URI))));
	});

	it('hints for == on the operator token, suggesting ===', () => {
		let r = check("let x = 1 $0==$1 2;\n");
		assert.match("Prefer '===' over '=='", r.want[0].message);
		assert.match(r.want, r.got);  // a HINT
	});

	it('hints for != and suggests !==', () => {
		let r = check("let x = 1 $0!=$1 2;\n");
		assert.match("Prefer '!==' over '!='", r.want[0].message);
		assert.match(r.want, r.got);
	});

	it('does not flag === or !==', () => {
		documents.open(URI, "let a = 1 === 1;\nlet b = 1 !== 2;\n", 1);

		assert.match(0, length(preferStrictEquality(documents.get(URI))));
	});

	it('reports one hint per operator', () => {
		let r = check("let a = 1 $0==$1 2;\nlet b = 3 $2!=$3 4;\n");
		assert.match(r.want, r.got);
	});

	it('finds == nested inside a function body', () => {
		let r = check("function f(x) { return x $0==$1 null; }\n");
		assert.match(r.want, r.got);
	});
});
