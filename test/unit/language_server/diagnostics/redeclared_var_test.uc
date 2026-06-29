import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { redeclaredVars } from 'language_server.diagnostics.redeclared_var';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — redeclared variables', () => {
	it('returns empty list when all names are unique', () => {
		assert.match(0, length(redeclaredVars(open("let x = 1;\nlet y = 2;\n"))));
	});

	it('errors on duplicate let in the same block', () => {
		let diags = redeclaredVars(open("let x = 1;\nlet x = 2;\n"));
		assert.match(1, length(diags));
		assert.match(1, diags[0].severity);   // ERROR
		assert.match('redeclared-var', diags[0].code);
		assert.match(true, index(diags[0].message, "'x'") >= 0);
	});

	it('does not error when same name is in a nested block', () => {
		let text = "let x = 1;\n{\n  let x = 2;\n}\n";
		assert.match(0, length(redeclaredVars(open(text))));
	});

	it('does not error for same name in separate nested blocks', () => {
		let text = "{\n  let x = 1;\n}\n{\n  let x = 2;\n}\n";
		assert.match(0, length(redeclaredVars(open(text))));
	});

	it('errors when a function-scoped name is redeclared in the same function body', () => {
		let text = "function f() {\n  let x = 1;\n  let x = 2;\n}\n";
		let diags = redeclaredVars(open(text));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'x'") >= 0);
	});

	it('reports the second (redeclaring) occurrence, not the first', () => {
		let diags = redeclaredVars(open("let x = 1;\nlet x = 2;\n"));
		// The diagnostic range is on line 1 (the redeclaration).
		assert.match(1, diags[0].range.start.line);
	});

	it('reports each additional redeclaration separately', () => {
		let diags = redeclaredVars(open("let x = 1;\nlet x = 2;\nlet x = 3;\n"));
		assert.match(2, length(diags));
	});

	it('does not confuse names across top-level and nested scope', () => {
		// Top-level x and function-body x are different scopes — fine.
		let text = "let x = 1;\nfunction f() {\n  let x = 2;\n}\n";
		assert.match(0, length(redeclaredVars(open(text))));
	});
});
