import { describe, it, assert } from 'utest';
import * as reporters from 'ucode_analyzer.linter.reporters';

// Two files: one with an error + a hint, one clean.
function sample() {
	return [
		{ uri: 'file:///ws/src/a.uc', diags: [
			{ range: { start: { line: 0, character: 4 } }, severity: 1, code: 'redeclared-var', message: 'x redeclared' },
			{ range: { start: { line: 2, character: 0 } }, severity: 4, code: 'unused-import',  message: 'unused import' },
		] },
		{ uri: 'file:///ws/src/b.uc', diags: [] },
	];
}

describe('reporters.formatText', () => {
	it('emits path:LINE:COL: [severity] message (code), 1-based, relative to root', () => {
		let out = reporters.formatText(sample(), '/ws');
		assert.match(
			"src/a.uc:1:5: [error] x redeclared (redeclared-var)\n" +
			"src/a.uc:3:1: [hint] unused import (unused-import)",
			out);
	});

	it('returns the empty string when there are no diagnostics', () => {
		assert.match('', reporters.formatText([{ uri: 'file:///ws/src/b.uc', diags: [] }], '/ws'));
	});

	it('falls back to the absolute path when the uri is not under root', () => {
		let out = reporters.formatText([{ uri: 'file:///other/x.uc', diags: [
			{ range: { start: { line: 0, character: 0 } }, severity: 2, code: 'dup', message: 'm' },
		] }], '/ws');
		assert.match('/other/x.uc:1:1: [warning] m (dup)', out);
	});
});

describe('reporters.formatJson', () => {
	it('produces [{ uri, diagnostics }] that round-trips through json()', () => {
		let parsed = json(reporters.formatJson(sample()));
		assert.match(2, length(parsed));
		assert.match('file:///ws/src/a.uc', parsed[0].uri);
		assert.match(2, length(parsed[0].diagnostics));
		assert.match('redeclared-var', parsed[0].diagnostics[0].code);
		assert.match(0, length(parsed[1].diagnostics));
	});
});

describe('reporters.summary', () => {
	it('tallies by severity and counts files with problems', () => {
		assert.match('1 error(s), 0 warning(s), 0 info, 1 hint(s) in 1 file(s).',
			reporters.summary(sample()));
	});

	it('reports a clean run', () => {
		assert.match('No problems found.', reporters.summary([{ uri: 'file:///ws/src/b.uc', diags: [] }]));
	});
});

describe('reporters.exitCode', () => {
	it('fails (1) when a diagnostic is at or above the threshold', () => {
		assert.match(1, reporters.exitCode(sample(), 'error'));   // has a severity-1 error
	});

	it('passes (0) when all diagnostics are below the threshold', () => {
		let hintOnly = [{ uri: 'file:///ws/a.uc', diags: [
			{ range: { start: { line: 0, character: 0 } }, severity: 4, code: 'h', message: 'm' },
		] }];
		assert.match(0, reporters.exitCode(hintOnly, 'error'));
		assert.match(1, reporters.exitCode(hintOnly, 'hint'));    // threshold lowered to hint
	});

	it('never fails when fail-on is none', () => {
		assert.match(0, reporters.exitCode(sample(), 'none'));
	});
});
