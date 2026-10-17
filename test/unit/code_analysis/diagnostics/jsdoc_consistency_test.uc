import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { jsdocConsistency } from 'ucode_analyzer.code_analysis.diagnostics.jsdoc_consistency';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function diags(text) {
	documents.open(URI, text, 1);
	return jsdocConsistency(documents.get(URI));
}
function count(text, code) {
	return length(filter(diags(text), (d) => d.code === code));
}

describe('diagnostics — jsdoc consistency: @param name mismatch', () => {
	it('is silent when the @param matches the parameter', () => {
		assert.match(0, length(diags("/** @param {int} x */\nfunction f(x) {}\n")));
	});

	it('flags a @param that names no parameter', () => {
		assert.match(1, count("/** @param {int} y */\nfunction f(x) {}\n", 'jsdoc-param-mismatch'));
	});

	it('works through an export statement', () => {
		assert.match(1, count("/** @param {int} wrong */\nexport function g(a) {}\n", 'jsdoc-param-mismatch'));
	});

	it('reports only the mismatching @param among several', () => {
		let d = diags("/** @param {int} a @param {int} wrong */\nfunction f(a, b) {}\n");
		assert.match(1, length(d));
		assert.match(true, index(d[0].message, "'wrong'") >= 0);
	});

	it('anchors the range on the offending name', () => {
		// `/** @param {int} y */` — 'y' is the 18th character (index 17) on line 0.
		let d = diags("/** @param {int} y */\nfunction f(x) {}\n");
		assert.match(0, d[0].range.start.line);
		assert.match(17, d[0].range.start.character);
		assert.match(18, d[0].range.end.character);
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
		assert.match(1, count("/** @param {int} first */\nfunction f(...args) {}\n", 'jsdoc-param-mismatch'));
	});

	it('flags a mismatch on a const-assigned function expression', () => {
		assert.match(1, count("/** @param {int} y */\nconst f = function(x) {};\n", 'jsdoc-param-mismatch'));
		assert.match(0, count("/** @param {int} x */\nconst f = function(x) {};\n", 'jsdoc-param-mismatch'));
	});

	it('flags a mismatch on an assigned arrow function', () => {
		assert.match(1, count("/** @param {int} y */\nlet f = (x) => x;\n", 'jsdoc-param-mismatch'));
		assert.match(0, count("/** @param {int} x */\nlet f = (x, ...r) => x;\n", 'jsdoc-param-mismatch'));
	});

	it('accepts the bare parameter of `x => …`', () => {
		assert.match(0, count("/** @param {int} x */\nlet f = x => x;\n", 'jsdoc-param-mismatch'));
		assert.match(1, count("/** @param {int} y */\nlet f = x => x;\n", 'jsdoc-param-mismatch'));
	});

	it('works through an exported const', () => {
		assert.match(1, count("/** @param {int} y */\nexport const f = function(x) {};\n", 'jsdoc-param-mismatch'));
	});

	it('skips a declaration with several declarators (the doc is ambiguous)', () => {
		assert.match(0, count("/** @param {int} x */\nconst f = function(x) {}, g = function(y) {};\n", 'jsdoc-param-mismatch'));
	});

	it('skips a function expression that is not the initializer itself', () => {
		assert.match(0, count("/** @param {int} y */\nconst f = wrap(function(x) {});\n", 'jsdoc-param-mismatch'));
	});
});

