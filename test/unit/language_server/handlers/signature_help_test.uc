import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { signatureHelp } from 'ucode_analyzer.language_server.handlers.signature_help';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';

let URI = 'file:///test.uc';

let _config = {
	workspaceDir: '/app',
	selfSrcDir: '/app/src/ucode_analyzer',
	workspace: { libraryPaths: ['src'] },
};

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	invalidateUri(URI);
});

describe('signatureHelp', () => {
	it('returns null when cursor is not inside a call', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		assert.match(null, signatureHelp(URI, documents.get(URI), { line: 0, character: 4 }));
	});

	it('returns null for an unknown function', () => {
		let text = "unknownFn(1, 2);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor inside arguments
		assert.match(null, signatureHelp(URI, documents.get(URI), { line: 0, character: 12 }));
	});

	it('returns signature for a known arrow function', () => {
		// Place cursor between the parens of add(
		let text = "let add = (x, y) => x + y;\nadd(1, 2);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor at line 1, char 4 — inside add(...)
		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 4 });

		assert.match(true, result !== null);
		assert.match(1, length(result.signatures));
		assert.match(0, result.activeSignature);
	});

	it('label contains the function name', () => {
		let text = "let greet = (name) => 'hi';\ngreet('world');\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 7 });

		assert.match(true, result !== null);
		assert.match(true, index(result.signatures[0].label, 'greet') >= 0);
	});

	it('activeParameter is 0 for first argument', () => {
		let text = "let f = (a, b) => a;\nf(1, 2);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor right after '(' — on first argument
		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 2 });

		assert.match(true, result !== null);
		assert.match(0, result.activeParameter);
	});

	it('activeParameter is 1 for second argument', () => {
		let text = "let f = (a, b) => a;\nf(1, 2);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on '2' (second argument) at char 5
		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 5 });

		assert.match(true, result !== null);
		assert.match(1, result.activeParameter);
	});

	it('parameters array has one entry per parameter', () => {
		let text = "let f = (a, b, c) => a;\nf(1, 2, 3);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 3 });

		assert.match(true, result !== null);
		assert.match(3, length(result.signatures[0].parameters));
	});

	it('activeParameter is null for a zero-parameter function', () => {
		let text = "function noParams() { return 1; }\nnoParams();\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 9 });

		assert.match(true, result !== null);
		assert.match(null, result.activeParameter);
	});

	it('parameter label offsets point to the correct substrings in the label', () => {
		// Each params[i].label = [s, e] must satisfy substr(label, s, e-s) == the param text.
		let text = "let f = (x, y) => x;\nf(1, 2);\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let result = signatureHelp(URI, documents.get(URI), { line: 1, character: 3 });

		assert.match(true, result !== null);
		let sig = result.signatures[0];
		assert.match(2, length(sig.parameters));
		for (let i = 0; i < length(sig.parameters); i++) {
			let s = sig.parameters[i].label[0];
			let e = sig.parameters[i].label[1];
			assert.match(true, s >= 0 && e > s && e <= length(sig.label));
			// The slice of the label must contain the param name.
			let slice = substr(sig.label, s, e - s);
			assert.match(true, index(slice, ['x', 'y'][i]) >= 0);
		}
	});

	it('parameter label offsets are correct for typed parameters', () => {
		// JSDoc annotated: label will be "greet(name: string)" — "name: string" at [6,18]
		let src = "/**\n * @param {string} name\n */\nfunction greet(name) {}\ngreet('x');\n";
		documents.open(URI, src, 1);
		dag.add(URI, src, documents.get(URI).tree);

		let result = signatureHelp(URI, documents.get(URI), { line: 4, character: 7 });

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
			'pair(1, 2);',
		];
		let src = join('\n', text) + '\n';
		documents.open(URI, src, 1);
		dag.add(URI, src, documents.get(URI).tree);

		// cursor on '2' (second arg) — T should be resolved to 'int' from first arg
		let result = signatureHelp(URI, documents.get(URI), { line: 7, character: 7 });

		assert.match(true, result !== null);
		assert.match(true, index(result.signatures[0].label, 'int') >= 0);
	});
});
