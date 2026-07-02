import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { missingReturn } from 'code_analysis.diagnostics.missing_return';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — missing return', () => {
	it('no warning for function without @returns', () => {
		let text = "function f() {\n  let x = 1;\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning for function with @returns that always returns', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f() {\n  return 1;\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warns for function with @returns that has no return', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f() {\n  let x = 1;\n}\n";
		let diags = missingReturn(open(text));
		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);  // WARNING
		assert.match('missing-return', diags[0].code);
	});

	it('warns when only one branch of if/else returns', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x) {\n  if (x) { return 1; }\n}\n";
		let diags = missingReturn(open(text));
		assert.match(1, length(diags));
		assert.match('missing-return', diags[0].code);
	});

	it('no warning when both if and else branches return', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x) {\n  if (x) { return 1; } else { return 2; }\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning when @returns is void', () => {
		let text = "/**\n * @returns {void}\n */\nfunction f() {\n  let x = 1;\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warns for if/else-if chain without final else', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x, y) {\n  if (x) { return 1; } else if (y) { return 2; }\n}\n";
		let diags = missingReturn(open(text));
		assert.match(1, length(diags));
	});

	it('no warning for if/else-if/else chain where all branches return', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x, y) {\n  if (x) { return 1; } else if (y) { return 2; } else { return 3; }\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warning points at function name', () => {
		let text = "/**\n * @returns {int}\n */\nfunction compute() {\n  let x = 1;\n}\n";
		let diags = missingReturn(open(text));
		assert.match(1, length(diags));
		assert.match(3, diags[0].range.start.line);  // function declaration line
	});

	it('no warning when a path ends in die()', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x) {\n  if (x) { return 1; }\n  die('nope');\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning when both branches terminate via return or exit()', () => {
		let text = "/**\n * @returns {int}\n */\nfunction f(x) {\n  if (x) { return 1; } else { exit(1); }\n}\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	// try/catch — ucode has no `finally` and a try must have a catch. The function
	// returns only if both the normal path and the catch path return.
	let DOC = "/** @returns {int} */\n";

	it('no warning when try and catch both return', () => {
		let text = DOC + "function f(s) { try { return +s; } catch (e) { return 0; } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warns when the catch clause does not return', () => {
		let text = DOC + "function f(s) { try { return +s; } catch (e) { print(e); } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	it('warns when the try body does not return', () => {
		let text = DOC + "function f(s) { try { print(s); } catch (e) { return 0; } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	// switch — ucode falls through C-style; a switch returns only with a default
	// and every clause (resolving fall-through) returning.
	it('no warning when a switch with default returns from every clause', () => {
		let text = DOC + "function f(x) { switch (x) { case 1: return 1; default: return 0; } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning for a fall-through case into a returning case', () => {
		let text = DOC + "function f(x) { switch (x) { case 1: case 2: return 9; default: return 0; } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warns for a switch with no default', () => {
		let text = DOC + "function f(x) { switch (x) { case 1: return 1; } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	it('warns when a switch clause breaks without returning', () => {
		let text = DOC + "function f(x) { switch (x) { case 1: break; default: return 0; } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	// infinite loops — a body ending in `while(true)`/`for(;;)` never falls
	// through, so no return is needed on the fall-through path. break-analysis is
	// intentionally not modeled (that would only ever miss a bug, never add a
	// false positive — precision over recall).
	it('no warning when the body ends in while (true)', () => {
		let text = DOC + "function f() { while (true) { doStuff(); } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning when the body ends in while (1)', () => {
		let text = DOC + "function f() { while (1) { doStuff(); } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('no warning when the body ends in for (;;)', () => {
		let text = DOC + "function f() { for (;;) { doStuff(); } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('warns for a while loop with a non-constant condition', () => {
		let text = DOC + "function f() { while (running) { doStuff(); } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	it('warns for a while (0) loop (never infinite)', () => {
		let text = DOC + "function f() { while (0) { doStuff(); } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	it('warns for a finite C-style for loop', () => {
		let text = DOC + "function f() { for (let i = 0; i < 10; i++) { doStuff(); } }\n";
		assert.match(1, length(missingReturn(open(text))));
	});

	it('no warning when while (true) follows other non-returning statements', () => {
		let text = DOC + "function f() { let x = 1; while (true) { doStuff(); } }\n";
		assert.match(0, length(missingReturn(open(text))));
	});

	it('still warns when a non-terminating statement follows the infinite loop', () => {
		// The loop is not the last statement, so control can reach the tail.
		let text = DOC + "function f() { while (true) { break; } let x = 1; }\n";
		assert.match(1, length(missingReturn(open(text))));
	});
});
