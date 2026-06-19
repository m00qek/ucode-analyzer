import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { completion } from 'ucode_language_server.completion';
import * as dag from 'ucode_language_server.dag';
import { invalidateUri } from 'ucode_language_server.memo';

let URI    = 'file:///test.uc';
let TS_URI = 'file:///app/src/tree_sitter.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(TS_URI);
	invalidateUri(URI);
});

describe('completion — scope', () => {
	beforeEach(() => dag.init(_config));

	it('offers local let binding at cursor', () => {
		let text = "let count = 0;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on line 1 — after the declaration
		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });

		let labels = map(items, (i) => i.label);
		assert.match(true, index(labels, 'count') >= 0);
	});

	it('completion item for a variable has VARIABLE kind (6)', () => {
		let text = "let x = 5;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let item = null;
		for (let i in items) if (i.label === 'x') { item = i; break; }

		assert.match(true, item !== null);
		assert.match(6, item.kind);
	});

	it('completion item for an arrow function has FUNCTION kind (3)', () => {
		let text = "let fn = x => x;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let item = null;
		for (let i in items) if (i.label === 'fn') { item = i; break; }

		assert.match(true, item !== null);
		assert.match(3, item.kind);
	});

	it('does not offer bindings declared after cursor', () => {
		// Cursor is at (1,0) = start of 'let b'; buildScope uses startByte < offset,
		// so 'let b' is excluded but 'let a' (which precedes it) is included.
		let text = "let a = 1;\nlet b = 2;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let labels = map(items, (i) => i.label);

		assert.match(true, index(labels, 'a') >= 0);
		assert.match(false, index(labels, 'b') >= 0);
	});
});

describe('completion — import context', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);  // populate tree_sitter exports
	});

	it('inside an import statement returns exports of the target module', () => {
		let text = "import { parse } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor at character 10 — inside the import_statement (on 'a' in 'parse')
		let items = completion(URI, documents.get(URI), { line: 0, character: 10 });

		assert.match(true, length(items) > 0);
	});

	it('outside an import statement offers scope locals not module exports', () => {
		let text = "import { parse } from 'tree_sitter';\nlet x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on line 2 — after 'let x = 1;', so x is in scope
		let items = completion(URI, documents.get(URI), { line: 2, character: 0 });

		let labels = map(items, (i) => i.label);
		assert.match(true, index(labels, 'x') >= 0);
	});
});
