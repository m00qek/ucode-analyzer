import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { syntaxErrors } from 'code_analysis.diagnostics.syntax_errors';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('diagnostics — syntax errors', () => {
	it('returns empty list for valid code', () => {
		let text = "let x = 1;\nfunction foo() { return x; }\n";
		documents.open(URI, text, 1);

		assert.match(0, length(syntaxErrors(documents.get(URI))));
	});

	it('reports an error for a missing closing brace', () => {
		let text = "function foo() {\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		assert.match(true, length(diags) > 0);
		assert.match(1, diags[0].severity);
	});

	it('reports an error for an invalid expression', () => {
		let text = "let x = ;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		assert.match(true, length(diags) > 0);
		assert.match(1, diags[0].severity);
	});

	it('diagnostic range points into the file', () => {
		let text = "let x = ;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));
		let r = diags[0].range;

		assert.match(0, r.start.line);
		assert.match(true, r.start.character >= 0);
	});

	it('message is Syntax error', () => {
		let text = "let x = ;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		assert.match('Syntax error', diags[0].message);
	});

	it('does not recurse into ERROR children (one diagnostic per top-level error node)', () => {
		// A single syntax error should produce one diagnostic, not one per sub-node.
		let text = "let = ;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		// Should be at least 1 but not an explosion of duplicates.
		assert.match(true, length(diags) >= 1);
		assert.match(true, length(diags) <= 3);
	});

	it('names the token of a MISSING node', () => {
		// A block left open at the end of the file gets a MISSING `}`.
		let text = "function foo() {\n\tlet x = 1;\n";
		documents.open(URI, text, 1);

		let diags = syntaxErrors(documents.get(URI));

		assert.match(1, length(diags));
		assert.match("Syntax error: missing '}'", diags[0].message);
	});
});
