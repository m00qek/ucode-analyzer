import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unreachableCode } from 'ucode_analyzer.code_analysis.diagnostics.unreachable_code';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// The warnings for a marked snippet: one per dead statement, on the marker
// pairs ($0,$1), ($2,$3), … in order.
function check(marked) {
	let src = cursors(marked), want = [];
	for (let i = 0; i + 1 < length(src.at); i += 2)
		push(want, {
			range: { start: src.at[i], end: src.at[i + 1] }, severity: 2, source: 'ucode-analyzer',
			code: 'unreachable-code', message: 'Unreachable code',
		});
	documents.open(URI, src.text, 1);
	return { want, got: unreachableCode(documents.get(URI)) };
}

describe('diagnostics — unreachable code', () => {
	it('returns empty list when no dead code exists', () => {
		documents.open(URI, "function f() {\n  let x = 1;\n  return x;\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('flags the whole statement after return, as a warning', () => {
		let r = check("function f() {\n  return 1;\n  $0let x = 2;$1\n}\n");
		assert.match(r.want, r.got);
	});

	it('flags a statement after break', () => {
		let r = check("for (let i = 0; i < 10; i++) {\n  break;\n  $0let x = 1;$1\n}\n");
		assert.match(r.want, r.got);
	});

	it('flags a statement after continue', () => {
		let r = check("for (let i = 0; i < 10; i++) {\n  continue;\n  $0let x = 1;$1\n}\n");
		assert.match(r.want, r.got);
	});

	it('flags multiple statements after return', () => {
		let r = check("function f() {\n  return 1;\n  $0let a = 2;$1\n  $2let b = 3;$3\n}\n");
		assert.match(r.want, r.got);
	});

	it('does not flag the return statement itself', () => {
		documents.open(URI, "function f() {\n  return 1;\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('does not flag code before the return', () => {
		let r = check("function f() {\n  let x = 1;\n  return x;\n  $0let y = 2;$1\n}\n");
		assert.match(r.want, r.got);
	});

	it('handles nested functions independently', () => {
		// Dead code in inner function does not affect outer, and vice versa.
		let r = check("function outer() {\n  function inner() {\n    return 1;\n    $0let x = 2;$1\n  }\n  let y = 3;\n}\n");
		assert.match(r.want, r.got);
	});

	it('returns empty list for top-level code with no blocks', () => {
		documents.open(URI, "let x = 1;\nlet y = 2;\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('does not flag a trailing comment after return (comment is not code)', () => {
		documents.open(URI, "function f() {\n  return 1;  // done\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('does not flag a comment on its own line after return', () => {
		documents.open(URI, "function f() {\n  return 1;\n  // trailing note\n}\n", 1);
		assert.match(0, length(unreachableCode(documents.get(URI))));
	});

	it('still flags real code that follows a comment after return', () => {
		// The comment must not "revive" the block: code after it is still dead.
		let r = check("function f() {\n  return 1;\n  // note\n  $0let x = 2;$1\n}\n");
		assert.match(r.want, r.got);
	});
});
