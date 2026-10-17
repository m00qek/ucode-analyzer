import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { assignmentToConst } from 'ucode_analyzer.code_analysis.diagnostics.const_assignment';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The errors for a marked snippet: `$0name$1` is the assigned identifier and
// `$2const$3` its declaration's keyword (the quick fix rewrites it).
function check(marked, name) {
	let src = cursors(marked);
	return {
		want: [{
			range: { start: src.at[0], end: src.at[1] }, severity: 1, source: 'ucode-analyzer',
			code: 'const-assignment', message: sprintf("Cannot assign to '%s' — it is declared const", name),
			data: { constKeywordRange: { start: src.at[2], end: src.at[3] } },
		}],
		got: assignmentToConst(open(src.text)),
	};
}

describe('diagnostics — assignment to const', () => {
	it('returns empty list for let reassignment', () => {
		assert.match(0, length(assignmentToConst(open("let x = 1;\nx = 2;\n"))));
	});

	it('errors on direct assignment to const, on the assigned identifier', () => {
		let r = check("$2const$3 x = 1;\n$0x$1 = 2;\n", 'x');
		assert.match(r.want, r.got);  // an ERROR
	});

	it('errors on augmented assignment to const', () => {
		let r = check("$2const$3 n = 0;\n$0n$1 += 1;\n", 'n');
		assert.match(r.want, r.got);
	});

	it('errors on update expression (++) on const', () => {
		let r = check("$2const$3 n = 0;\n$0n$1++;\n", 'n');
		assert.match(r.want, r.got);
	});

	it('inner block can shadow a const with a let', () => {
		let text = "const x = 1;\nfunction f() {\n  let x = 2;\n  x = 3;\n}\n";
		assert.match(0, length(assignmentToConst(open(text))));
	});

	it('inner block cannot reassign outer const when not shadowed', () => {
		let r = check("$2const$3 x = 1;\nfunction f() {\n  $0x$1 = 2;\n}\n", 'x');
		assert.match(r.want, r.got);
	});

	it('const declared in inner scope: error only within that scope', () => {
		let r = check("function f() {\n  $2const$3 y = 1;\n  $0y$1 = 2;\n}\n", 'y');
		assert.match(r.want, r.got);
	});

	it('no false positive for const used in a read-only way', () => {
		let text = "const MAX = 100;\nlet y = MAX + 1;\ny;\n";
		assert.match(0, length(assignmentToConst(open(text))));
	});

	it('checks the right side of an assignment after a comment', () => {
		let r = check("$2const$3 y = 1;\nlet x;\nx /* c */ = ($0y$1 = 2);\n", 'y');
		assert.match(r.want, r.got);
	});
});
