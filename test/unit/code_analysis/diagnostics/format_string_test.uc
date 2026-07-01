import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { formatString } from 'code_analysis.diagnostics.format_string';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function diags(text) {
	documents.open(URI, text, 1);
	return formatString(documents.get(URI));
}
function count(text, code) {
	return length(filter(diags(text), (d) => d.code === code));
}

describe('diagnostics — format string: length modifiers', () => {
	it('flags %ld', () => {
		assert.match(1, count('sprintf("%ld", n);', 'invalid-format-specifier'));
	});
	it('flags %lld and %zu', () => {
		assert.match(1, count('printf("%lld", n);', 'invalid-format-specifier'));
		assert.match(1, count('printf("%zu", n);',  'invalid-format-specifier'));
	});
	it('does not flag a plain %d', () => {
		assert.match(0, length(diags('sprintf("%d", n);')));
	});
	it('length modifier suppresses the arg-count check (no double report)', () => {
		assert.match(0, count('sprintf("%ld", n);', 'format-argument-count'));
	});
});

describe('diagnostics — format string: argument count', () => {
	it('flags too few arguments', () => {
		assert.match(1, count('printf("%d %s", x);', 'format-argument-count'));
	});
	it('flags too many arguments', () => {
		assert.match(1, count('sprintf("%d", a, b);', 'format-argument-count'));
	});
	it('accepts an exact match', () => {
		assert.match(0, length(diags('sprintf("%d %s", a, b);')));
	});
	it('%% does not consume an argument', () => {
		assert.match(0, length(diags('printf("%d%%", n);')));
	});
	it('flags a literal percent ucode misformats ("20% done")', () => {
		// ucode reads "% d" as a space-flagged %d, so this really consumes an arg.
		assert.match(1, count('sprintf("20% done");', 'format-argument-count'));
	});
	it('flags a format with conversions and no arguments', () => {
		assert.match(1, count('printf("%d\\n");', 'format-argument-count'));
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
