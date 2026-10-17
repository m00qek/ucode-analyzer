import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { jsdocConsistency } from 'ucode_analyzer.code_analysis.diagnostics.jsdoc_param_mismatch';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function diags(text) {
	documents.open(URI, text, 1);
	return jsdocConsistency(documents.get(URI));
}
// The warnings for a snippet whose mismatching @param name is marked `$0name$1`.
function check(marked) {
	let src = cursors(marked);
	let name = substr(src.text, src.offset[0], src.offset[1] - src.offset[0]);
	return {
		want: [{
			range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
			code: 'jsdoc-param-mismatch', message: sprintf("@param '%s' does not match any parameter of this function", name),
		}],
		got: diags(src.text),
	};
}

describe('diagnostics — jsdoc consistency: @param name mismatch', () => {
	it('is silent when the @param matches the parameter', () => {
		assert.match(0, length(diags("/** @param {int} x */\nfunction f(x) {}\n")));
	});

	it('flags a @param that names no parameter', () => {
		let r = check("/** @param {int} $0y$1 */\nfunction f(x) {}\n");
		assert.match(r.want, r.got);
	});

	it('works through an export statement', () => {
		let r = check("/** @param {int} $0wrong$1 */\nexport function g(a) {}\n");
		assert.match(r.want, r.got);
	});

	it('reports only the mismatching @param among several', () => {
		let r = check("/** @param {int} a @param {int} $0wrong$1 */\nfunction f(a, b) {}\n");
		assert.match(r.want, r.got);
	});

});

describe('diagnostics — jsdoc consistency: no false positives', () => {
	it('accepts an optional [x] that matches', () => {
		assert.match(0, length(diags("/** @param {int} [x] */\nfunction f(x) {}\n")));
	});

	it('accepts a rest ...args that matches the rest parameter', () => {
		assert.match(0, length(diags("/** @param {...int} args */\nfunction f(...args) {}\n")));
	});

	it('accepts a property path whose root is a real parameter', () => {
		// `opts.count` documents a property of `opts`; its root `opts` is a parameter.
		assert.match(0, length(diags(
			"/** @param {object} opts @param {int} opts.count */\nfunction f(opts) {}\n")));
	});

	it('does not flag a parameter that simply lacks a @param (incomplete docs)', () => {
		assert.match(0, length(diags("/** @param {int} a */\nfunction f(a, b) {}\n")));
	});

	it('is silent for a function with no doc comment', () => {
		assert.match(0, length(diags("function f(x) {}\n")));
	});

	it('is silent for a doc comment with no @param tags', () => {
		assert.match(0, length(diags("/** Frobs the widget. */\nfunction f(x) {}\n")));
	});

	it('still flags a bad name when the parameter is a rest element', () => {
		// `first` is not the rest parameter `args`, so it is a genuine mismatch.
		let r = check("/** @param {int} $0first$1 */\nfunction f(...args) {}\n");
		assert.match(r.want, r.got);
	});

	it('flags a mismatch on a const-assigned function expression', () => {
		let r = check("/** @param {int} $0y$1 */\nconst f = function(x) {};\n");
		assert.match(r.want, r.got);
		assert.match([], diags("/** @param {int} x */\nconst f = function(x) {};\n"));
	});

	it('flags a mismatch on an assigned arrow function', () => {
		let r = check("/** @param {int} $0y$1 */\nlet f = (x) => x;\n");
		assert.match(r.want, r.got);
		assert.match([], diags("/** @param {int} x */\nlet f = (x, ...r) => x;\n"));
	});

	it('accepts the bare parameter of `x => …`', () => {
		assert.match([], diags("/** @param {int} x */\nlet f = x => x;\n"));
		let r = check("/** @param {int} $0y$1 */\nlet f = x => x;\n");
		assert.match(r.want, r.got);
	});

	it('works through an exported const', () => {
		let r = check("/** @param {int} $0y$1 */\nexport const f = function(x) {};\n");
		assert.match(r.want, r.got);
	});

	it('skips a declaration with several declarators (the doc is ambiguous)', () => {
		assert.match([], diags("/** @param {int} x */\nconst f = function(x) {}, g = function(y) {};\n"));
	});

	it('skips a function expression that is not the initializer itself', () => {
		assert.match([], diags("/** @param {int} y */\nconst f = wrap(function(x) {});\n"));
	});
});

