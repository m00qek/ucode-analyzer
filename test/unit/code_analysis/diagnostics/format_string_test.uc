import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { formatString } from 'ucode_analyzer.code_analysis.diagnostics.format_string';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function diags(text) {
	documents.open(URI, text, 1);
	return formatString(URI, documents.get(URI));
}
// The one warning a snippet raises, on the range marked `$0…$1`, and what the
// check reports.
function check(marked, code, message) {
	let src = cursors(marked);
	return {
		want: [{ range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer', code, message }],
		got: diags(src.text),
	};
}

describe('diagnostics — format string: length modifiers', () => {
	it('flags %ld', () => {
		let r = check('sprintf($0"%ld"$1, n);', 'invalid-format-specifier', "Format specifier '%ld' uses a length modifier, which ucode does not support — it is printed literally");
		assert.match(r.want, r.got);
	});
	it('flags %lld and %zu', () => {
		let r = check('printf($0"%lld"$1, n);', 'invalid-format-specifier', "Format specifier '%lld' uses a length modifier, which ucode does not support — it is printed literally");
		assert.match(r.want, r.got);
		r = check('printf($0"%zu"$1, n);', 'invalid-format-specifier', "Format specifier '%zu' uses a length modifier, which ucode does not support — it is printed literally");
		assert.match(r.want, r.got);
	});
	it('does not flag a plain %d', () => {
		assert.match(0, length(diags('sprintf("%d", n);')));
	});
	it('length modifier suppresses the arg-count check (no double report)', () => {
		let r = check('sprintf($0"%ld"$1, n);', 'invalid-format-specifier', "Format specifier '%ld' uses a length modifier, which ucode does not support — it is printed literally");
		assert.match(r.want, r.got);
	});
});

describe('diagnostics — format string: argument count', () => {
	it('flags too few arguments', () => {
		let r = check('printf($0"%d %s"$1, x);', 'format-argument-count', 'Format string expects 2 argument(s) but 1 given');
		assert.match(r.want, r.got);
	});
	it('flags too many arguments', () => {
		let r = check('sprintf($0"%d"$1, a, b);', 'format-argument-count', 'Format string expects 1 argument(s) but 2 given');
		assert.match(r.want, r.got);
	});
	it('accepts an exact match', () => {
		assert.match(0, length(diags('sprintf("%d %s", a, b);')));
	});
	it('%% does not consume an argument', () => {
		assert.match(0, length(diags('printf("%d%%", n);')));
	});
	it('flags a literal percent ucode misformats ("20% done")', () => {
		// ucode reads "% d" as a space-flagged %d, so this really consumes an arg.
		let r = check('sprintf($0"20% done"$1);', 'format-argument-count', 'Format string expects 1 argument(s) but 0 given');
		assert.match(r.want, r.got);
	});
	it('flags a format with conversions and no arguments', () => {
		let r = check('printf($0"%d\\n"$1);', 'format-argument-count', 'Format string expects 1 argument(s) but 0 given');
		assert.match(r.want, r.got);
	});
});

describe('diagnostics — format string: correctly silent', () => {
	it('trailing percent is literal', () => {
		assert.match(0, length(diags('sprintf("rate 5%");')));
	});
	it('percent before a non-conversion char is literal', () => {
		assert.match(0, length(diags('sprintf("100%!");')));
	});
	it('positional args skip the arg-count check', () => {
		assert.match(0, length(diags('sprintf("%2$s %1$d", a, b);')));
	});
	it('escape adjacent to a percent stays literal ("50%\\n")', () => {
		assert.match(0, length(diags('sprintf("50%\\n");')));
	});
	it('a spread argument skips the arg-count check', () => {
		assert.match(0, length(diags('sprintf("%d %d", ...xs);')));
	});
	it('a non-literal format string is ignored', () => {
		assert.match(0, length(diags('sprintf(fmt, a, b);')));
	});
	it('only sprintf/printf are checked', () => {
		assert.match(0, length(diags('myfunc("%d %d", x);')));
	});
});

describe('diagnostics — format string: argument type', () => {
	it('flags an array literal passed to %d', () => {
		let r = check('sprintf("%d", $0[1,2]$1);', 'format-argument-type', "Conversion '%d' expects a number but its argument is a list");
		assert.match(r.want, r.got);
	});
	it('flags an object literal passed to %x', () => {
		let r = check('sprintf("%x", $0{a:1}$1);', 'format-argument-type', "Conversion '%x' expects a number but its argument is a record");
		assert.match(r.want, r.got);
	});
	it('flags a function passed to %d', () => {
		let r = check('function f() {}\nsprintf("%d", $0f$1);', 'format-argument-type', "Conversion '%d' expects a number but its argument is a function");
		assert.match(r.want, r.got);
	});
	it('does NOT flag a structured value passed to %s', () => {
		assert.match([], diags('sprintf("%s", [1,2]);'));
	});
	it('does NOT flag a structured value passed to %J', () => {
		assert.match([], diags('sprintf("%J", {a:1});'));
	});
	it('does NOT flag an integer passed to %d', () => {
		assert.match([], diags('sprintf("%d", 5);'));
	});
	it('does NOT flag a string passed to %d (coercion is ambiguous)', () => {
		assert.match([], diags('sprintf("%d", "42");'));
	});
	it('does NOT flag an unknown-typed argument', () => {
		assert.match([], diags('sprintf("%d", x);'));
	});
	it('maps conversions to arguments by position', () => {
		// %s accepts the list; %d gets the record -> exactly one type warning
		let r = check('sprintf("%s %d", [1], $0{a:1}$1);', 'format-argument-type', "Conversion '%d' expects a number but its argument is a record");
		assert.match(r.want, r.got);
	});
});
