import { describe, it, assert } from 'utest';
import { runPass } from 'ucode_analyzer.code_analysis.diagnostics';

// runPass isolates one diagnostic pass: a die()/runtime error in a pass must not
// propagate (which would drop the other passes and abort a workspace scan). On
// failure the pass contributes nothing and logs to stderr. (Expect a couple of
// 'diagnostic ... failed' lines on stderr while these run — that is the log.)
describe('diagnostics — pass isolation (runPass)', () => {
	it('appends the results of a passing pass', () => {
		let out = [];
		runPass('ok', 'file:///t.uc', () => [{ code: 'a' }, { code: 'b' }], out);
		assert.match(2, length(out));
	});

	it('swallows a die() and contributes nothing', () => {
		let out = [];
		runPass('boom', 'file:///t.uc', () => die('kaboom'), out);
		assert.match(0, length(out));
	});

	it('swallows a runtime error (null dereference)', () => {
		let out = [];
		let empty = [];
		// empty[0] is null at runtime; dereferencing it throws. (Routed through a
		// subscript so it is a genuine runtime error, not a static null.)
		runPass('nullderef', 'file:///t.uc', () => empty[0].foo, out);
		assert.match(0, length(out));
	});

	it('keeps earlier results and continues after a failing pass', () => {
		let out = [];
		runPass('ok1',  'file:///t.uc', () => [{ code: 'a' }], out);
		runPass('boom', 'file:///t.uc', () => die('x'), out);
		runPass('ok2',  'file:///t.uc', () => [{ code: 'c' }], out);
		assert.match(2, length(out));
		assert.match('a', out[0].code);
		assert.match('c', out[1].code);
	});
});
