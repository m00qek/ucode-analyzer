import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { signatureHelp } from 'ucode_analyzer.language_server.handlers.signature_help';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

beforeEach(() => dag.init(fixture.config()));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	invalidateUri(URI);
});

// Open the marked text, add it to the DAG and ask for signature help at $0.
function sigAt(marked) {
	let src = cursors(marked);
	documents.open(URI, src.text, 1);
	dag.add(URI, src.text, documents.get(URI).tree);
	return signatureHelp(URI, documents.get(URI), src.at[0]);
}

describe('signatureHelp', () => {
	it('returns null when cursor is not inside a call', () => {
		assert.match(null, sigAt("let $0x = 1;\n"));
	});

	it('returns null for an unknown function', () => {
		// inside the arguments
		assert.match(null, sigAt("unknownFn(1,$0 2);\n"));
	});

	it('returns signature for a known arrow function', () => {
		// inside add(...)
		let result = sigAt("let add = (x, y) => x + y;\nadd($01, 2);\n");

		assert.match(true, result !== null);
		assert.match(1, length(result.signatures));
		assert.match(0, result.activeSignature);
	});

	it('label contains the function name', () => {
		let result = sigAt("let greet = (name) => 'hi';\ngreet('$0world');\n");

		assert.match(true, result !== null);
		assert.match(contains('greet'), result.signatures[0].label);
	});

	it('activeParameter is 0 for first argument', () => {
		// right after '(' — on the first argument
		let result = sigAt("let f = (a, b) => a;\nf($01, 2);\n");

		assert.match(true, result !== null);
		assert.match(0, result.activeParameter);
	});

	it('activeParameter is 1 for second argument', () => {
		let result = sigAt("let f = (a, b) => a;\nf(1, $02);\n");

		assert.match(true, result !== null);
		assert.match(1, result.activeParameter);
	});

	it('parameters array has one entry per parameter', () => {
		let result = sigAt("let f = (a, b, c) => a;\nf(1$0, 2, 3);\n");

		assert.match(true, result !== null);
		assert.match(3, length(result.signatures[0].parameters));
	});

	it('activeParameter is null for a zero-parameter function', () => {
		let result = sigAt("function noParams() { return 1; }\nnoParams($0);\n");

		assert.match(true, result !== null);
		assert.match(null, result.activeParameter);
	});

	it('parameter label offsets point to the correct substrings in the label', () => {
		// Each params[i].label = [s, e] must satisfy substr(label, s, e-s) == the param text.
		let result = sigAt("let f = (x, y) => x;\nf(1$0, 2);\n");

		assert.match(true, result !== null);
		let sig = result.signatures[0];
		assert.match(2, length(sig.parameters));
		for (let i = 0; i < length(sig.parameters); i++) {
			let s = sig.parameters[i].label[0];
			let e = sig.parameters[i].label[1];
			assert.match(true, s >= 0 && e > s && e <= length(sig.label));
			// The slice of the label must contain the param name.
			let slice = substr(sig.label, s, e - s);
			assert.match(contains(['x', 'y'][i]), slice);
		}
	});

	it('parameter label offsets are correct for typed parameters', () => {
		// JSDoc annotated: label will be "greet(name: string)" — "name: string" at [6,18]
		let result = sigAt("/**\n * @param {string} name\n */\nfunction greet(name) {}\ngreet('$0x');\n");

		assert.match(true, result !== null);
		let label = result.signatures[0].label;
		let params = result.signatures[0].parameters;
		assert.match(1, length(params));
		// "name: string" starts after "greet(" (6 chars)
		assert.match(6, params[0].label[0]);
		assert.match(18, params[0].label[1]);
		// verify the substring actually matches
		assert.match('name: string', substr(label, params[0].label[0], params[0].label[1] - params[0].label[0]));
	});

	it('resolves generic T to the concrete type inferred from the first argument', () => {
		// arrow functions in let bindings do not pick up JSDoc; function declarations do.
		let text = [
			'/**',
			' * @template T',
			' * @param {T} a',
			' * @param {T} b',
			' * @returns {T}',
			' */',
			'function pair(a, b) { return a; }',
			'pair(1,$0 2);',
		];

		// in the second argument — T should be resolved to 'int' from the first
		let result = sigAt(join('\n', text) + '\n');

		assert.match(true, result !== null);
		assert.match(contains('int'), result.signatures[0].label);
	});
});
