import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { assignmentToConst } from 'code_analysis.diagnostics.assignment_const';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — assignment to const', () => {
	it('returns empty list for let reassignment', () => {
		assert.match(0, length(assignmentToConst(open("let x = 1;\nx = 2;\n"))));
	});

	it('errors on direct assignment to const', () => {
		let diags = assignmentToConst(open("const x = 1;\nx = 2;\n"));
		assert.match(1, length(diags));
		assert.match(1, diags[0].severity);  // ERROR
		assert.match('const-assignment', diags[0].code);
		assert.match(true, index(diags[0].message, "'x'") >= 0);
	});

	it('errors on augmented assignment to const', () => {
		let diags = assignmentToConst(open("const n = 0;\nn += 1;\n"));
		assert.match(1, length(diags));
		assert.match('const-assignment', diags[0].code);
	});

	it('errors on update expression (++) on const', () => {
		let diags = assignmentToConst(open("const n = 0;\nn++;\n"));
		assert.match(1, length(diags));
		assert.match('const-assignment', diags[0].code);
	});

	it('inner block can shadow a const with a let', () => {
		let text = "const x = 1;\nfunction f() {\n  let x = 2;\n  x = 3;\n}\n";
		assert.match(0, length(assignmentToConst(open(text))));
	});

	it('inner block cannot reassign outer const when not shadowed', () => {
		let text = "const x = 1;\nfunction f() {\n  x = 2;\n}\n";
		let diags = assignmentToConst(open(text));
		assert.match(1, length(diags));
		assert.match('const-assignment', diags[0].code);
	});

	it('const declared in inner scope: error only within that scope', () => {
		let text = "function f() {\n  const y = 1;\n  y = 2;\n}\n";
		let diags = assignmentToConst(open(text));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'y'") >= 0);
	});

	it('reports range on the identifier being assigned', () => {
		let diags = assignmentToConst(open("const x = 1;\nx = 2;\n"));
		assert.match(1, diags[0].range.start.line);
		assert.match(0, diags[0].range.start.character);
	});

	it('no false positive for const used in a read-only way', () => {
		let text = "const MAX = 100;\nlet y = MAX + 1;\ny;\n";
		assert.match(0, length(assignmentToConst(open(text))));
	});

	it('checks the right side of an assignment after a comment', () => {
		let diags = assignmentToConst(open("const y = 1;\nlet x;\nx /* c */ = (y = 2);\n"));
		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, "'y'") >= 0);
	});
});
