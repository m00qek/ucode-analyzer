import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { missingReturn } from 'language_server.handlers.diagnostics.missing_return';

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
});
