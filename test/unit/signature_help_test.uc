import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { signatureHelp } from 'ucode_language_server.signature_help';
import * as dag from 'ucode_language_server.dag';
import { invalidateUri } from 'ucode_language_server.memo';

let URI = 'file:///test.uc';

let _config = {
	workspaceDir: '/app',
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
});
