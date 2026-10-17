import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { redeclaredVars } from 'ucode_analyzer.code_analysis.diagnostics.redeclared_var';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The errors for a marked snippet: one per redeclaration of `name`, on the
// marker pairs ($0,$1), ($2,$3), … in order.
function check(marked, name) {
	let src = cursors(marked), want = [];
	for (let i = 0; i + 1 < length(src.at); i += 2)
		push(want, {
			range: { start: src.at[i], end: src.at[i + 1] }, severity: 1, source: 'ucode-analyzer',
			code: 'redeclared-var', message: sprintf("'%s' is already declared in this scope", name),
		});
	return { want, got: redeclaredVars(open(src.text)) };
}

describe('diagnostics — redeclared variables', () => {
	it('returns empty list when all names are unique', () => {
		assert.match(0, length(redeclaredVars(open("let x = 1;\nlet y = 2;\n"))));
	});

	it('errors on duplicate let in the same block, on the redeclaration', () => {
		let r = check("let x = 1;\nlet $0x$1 = 2;\n", 'x');
		assert.match(r.want, r.got);  // an ERROR
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
		let r = check("function f() {\n  let x = 1;\n  let $0x$1 = 2;\n}\n", 'x');
		assert.match(r.want, r.got);
	});

	it('reports each additional redeclaration separately', () => {
		let r = check("let x = 1;\nlet $0x$1 = 2;\nlet $2x$3 = 3;\n", 'x');
		assert.match(r.want, r.got);
	});

	it('does not confuse names across top-level and nested scope', () => {
		// Top-level x and function-body x are different scopes — fine.
		let text = "let x = 1;\nfunction f() {\n  let x = 2;\n}\n";
		assert.match(0, length(redeclaredVars(open(text))));
	});

	it('errors on a duplicate let at a template\'s top level', () => {
		let r = check("{% let x = 1; %}\n<p>{{ x }}</p>\n{% let $0x$1 = 2; %}\n", 'x');
		assert.match(r.want, r.got);
	});
});
