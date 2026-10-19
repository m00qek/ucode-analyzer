import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { typeNameChecks } from 'ucode_analyzer.code_analysis.diagnostics.type_name';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function messages(text) {
	documents.open(URI, text, 1);
	return map(typeNameChecks(documents.get(URI)), (d) => d.message);
}

describe('diagnostics — names type() never returns', () => {
	it('flags the name, at its literal', () => {
		let src = cursors("let x = 1;\nif (type(x) == $0'integer'$1) print(x);\n");
		documents.open(URI, src.text, 1);
		assert.match([{
			range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
			code: 'impossible-type-check', message: "type() never returns 'integer': did you mean 'int'?",
		}], typeNameChecks(documents.get(URI)));
	});

	it("explains 'null', and names without a likely meaning", () => {
		assert.match([ "type() never returns 'null': for null it returns null itself, so compare with null" ],
			messages("let x;\nif ('null' === type(x)) x = 1;\n"));
		assert.match([ "type() never returns 'thing'" ], messages("let x;\nif (type(x) != 'thing') x = 1;\n"));
	});

	it('checks the cases of a switch on type()', () => {
		assert.match([ "type() never returns 'boolean': did you mean 'bool'?" ],
			messages("let x;\nswitch (type(x)) {\ncase 'string': break;\ncase 'boolean': break;\ndefault: break;\n}\n"));
	});

	it('accepts every name type() returns, and other comparisons', () => {
		let names = [ 'int', 'double', 'bool', 'string', 'array', 'object', 'function', 'regexp', 'resource' ];
		assert.match([], messages(join('', map(names, (n) => sprintf("type(x) == '%s';\n", n))) + "let x;\n"));
		assert.match([], messages("let x, y;\nif (x == 'integer' || type(x) == y || type(x) == null) x = 1;\n"));
	});

	it('leaves a local function named type alone', () => {
		assert.match([], messages("function type(v) { return 'integer'; }\nif (type(1) == 'integer') print(1);\n"));
	});
});
