import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { syntaxErrors } from 'ucode_analyzer.code_analysis.diagnostics.syntax_error';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// The whole error diagnostic for the range between markers $0 and $1.
function syntaxError(src, message) {
	return { range: { start: src.at[0], end: src.at[1] }, severity: 1, source: 'ucode-analyzer',
		code: 'syntax-error', message };
}

describe('diagnostics — syntax errors', () => {
	it('returns empty list for valid code', () => {
		let text = "let x = 1;\nfunction foo() { return x; }\n";
		documents.open(URI, text, 1);

		assert.match(0, length(syntaxErrors(documents.get(URI))));
	});

	it('reports an error for a missing closing brace', () => {
		let src = cursors("function foo() {\n$0$1");
		documents.open(URI, src.text, 1);

		assert.match([syntaxError(src, "Syntax error: missing '}'")], syntaxErrors(documents.get(URI)));
	});

	it('reports an error for an invalid expression', () => {
		let src = cursors("let x $0=$1 ;\n");
		documents.open(URI, src.text, 1);

		assert.match([syntaxError(src, 'Syntax error')], syntaxErrors(documents.get(URI)));
	});

	it('message is Syntax error', () => {
		let text = "let x = ;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		assert.match('Syntax error', diags[0].message);
	});

	it('does not recurse into ERROR children (one diagnostic per top-level error node)', () => {
		// A single syntax error should produce one diagnostic, not one per sub-node.
		let src = cursors("$0let =$1 ;\n");
		documents.open(URI, src.text, 1);

		assert.match([syntaxError(src, 'Syntax error')], syntaxErrors(documents.get(URI)));
	});

	it('names the token of a MISSING node', () => {
		// A block left open at the end of the file gets a MISSING `}`.
		let src = cursors("function foo() {\n\tlet x = 1;\n$0$1");
		documents.open(URI, src.text, 1);

		assert.match([syntaxError(src, "Syntax error: missing '}'")], syntaxErrors(documents.get(URI)));
	});
});
