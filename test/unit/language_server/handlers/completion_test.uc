import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { completion } from 'language_server.handlers.completion';
import * as dag from 'language_server.dag.dag';
import { invalidateUri } from 'language_server.memo';

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

		// tree_sitter exports many symbols; falling through to importedItems would
		// return only {parse} (1 item), so > 1 distinguishes the two paths.
		assert.match(true, length(items) > 1);
	});

	it('outside an import statement offers scope locals and named imports', () => {
		let text = "import { parse } from 'tree_sitter';\nlet x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor on line 2 — after 'let x = 1;', so x is in scope
		let items = completion(URI, documents.get(URI), { line: 2, character: 0 });

		let labels = map(items, (i) => i.label);
		assert.match(true, index(labels, 'x') >= 0);      // local binding
		assert.match(true, index(labels, 'parse') >= 0);  // named import
	});
});

describe('completion — member (cursor on property)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(TS_URI);
	});

	it('namespace import: offers exports of the module, not all scope items', () => {
		// Cursor on 'parse' in 'ts.parse' — should return ts members only.
		let text = "import * as ts from 'tree_sitter';\nlet x = 5;\nts.parse";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// line 2, character 3 — on 'p' of 'parse'
		let items = completion(URI, documents.get(URI), { line: 2, character: 3 });
		let labels = map(items, (i) => i.label);

		assert.match(true, index(labels, 'parse') >= 0);   // ts export
		assert.match(false, index(labels, 'x') >= 0);      // local binding — must NOT appear
	});

	it('namespace import: items include the function kind for function exports', () => {
		let text = "import * as ts from 'tree_sitter';\nts.parse";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 3 });
		let item = null;
		for (let i in items) if (i.label === 'parse') { item = i; break; }

		assert.match(true, item !== null);
		assert.match(3, item.kind);  // KIND_FUNCTION
	});

	it('trigger character: cursor right after dot returns members', () => {
		// 'ts.' — no property typed yet; offset is right after the dot.
		let text = "import * as ts from 'tree_sitter';\nts.\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// line 1, character 3 — right after 'ts.'
		let items = completion(URI, documents.get(URI), { line: 1, character: 3 });
		let labels = map(items, (i) => i.label);

		assert.match(true, index(labels, 'parse') >= 0);
	});

	it('record type: offers field names of an object literal', () => {
		// 'obj.foo' — obj is a local record-typed binding.
		let text = "let obj = { foo: function() {}, bar: function() {} };\nobj.foo";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// line 1, character 4 — on 'f' of 'foo'
		let items = completion(URI, documents.get(URI), { line: 1, character: 4 });
		let labels = map(items, (i) => i.label);

		assert.match(true, index(labels, 'foo') >= 0);
		assert.match(true, index(labels, 'bar') >= 0);
	});

	it('record type: does not include scope locals', () => {
		let text = "let x = 99;\nlet obj = { foo: 1 };\nobj.foo";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 2, character: 4 });
		let labels = map(items, (i) => i.label);

		assert.match(true,  index(labels, 'foo') >= 0);
		assert.match(false, index(labels, 'x') >= 0);
	});

	it('non-member position still returns general items', () => {
		let text = "import * as ts from 'tree_sitter';\nlet x = 5;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// line 2 — plain identifier position, not a member expression
		let items = completion(URI, documents.get(URI), { line: 2, character: 0 });
		let labels = map(items, (i) => i.label);

		assert.match(true, index(labels, 'x') >= 0);
		assert.match(true, index(labels, 'ts') >= 0);  // namespace alias is in scope
	});
});

describe('completion — keywords', () => {
	beforeEach(() => dag.init(_config));

	it('includes language keywords in general completion', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let labels = map(items, (i) => i.label);

		// A selection of expected keywords
		assert.match(true, index(labels, 'if') >= 0);
		assert.match(true, index(labels, 'for') >= 0);
		assert.match(true, index(labels, 'while') >= 0);
		assert.match(true, index(labels, 'return') >= 0);
		assert.match(true, index(labels, 'let') >= 0);
		assert.match(true, index(labels, 'function') >= 0);
		assert.match(true, index(labels, 'true') >= 0);
		assert.match(true, index(labels, 'null') >= 0);
	});

	it('keyword items have KEYWORD kind (14)', () => {
		let text = "let x = 1;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let ifItem = null;
		for (let i in items) if (i.label === 'if') { ifItem = i; break; }

		assert.match(true, ifItem !== null);
		assert.match(14, ifItem.kind);
	});

	it('does not include keywords inside member expression context', () => {
		let text = "let obj = {};\nobj.";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor right after the dot — member context, no keywords expected
		let items = completion(URI, documents.get(URI), { line: 1, character: 4 });
		let labels = map(items, (i) => i.label);

		assert.match(false, index(labels, 'if') >= 0);
		assert.match(false, index(labels, 'return') >= 0);
	});

	it('does not include keywords inside import statement context', () => {
		// Cursor inside the module specifier string
		let text = "import { x } from 'tree_sitter';\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		// cursor at position 19, inside 'tree_sitter' string
		let items = completion(URI, documents.get(URI), { line: 0, character: 19 });
		let labels = map(items, (i) => i.label);

		assert.match(false, index(labels, 'if') >= 0);
	});
});

describe('completion — snippets', () => {
	beforeEach(() => dag.init(_config));

	it('function items have insertTextFormat 2 (Snippet)', () => {
		let text = "/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 5, character: 0 });
		let item = filter(items, (i) => i.label === 'add')[0];
		assert.match(true, item !== null);
		assert.match(2, item.insertTextFormat);
	});

	it('snippet includes param names from JSDoc for scope items', () => {
		let text = "/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 5, character: 0 });
		let item = filter(items, (i) => i.label === 'add')[0];
		assert.match(true, index(item.insertText, 'x') >= 0);
		assert.match(true, index(item.insertText, 'y') >= 0);
		assert.match('add(${1:x}, ${2:y})', item.insertText);
	});

	it('zero-param function gets empty parens snippet', () => {
		let text = "function ping() { return true; }\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let item = filter(items, (i) => i.label === 'ping')[0];
		assert.match('ping()', item.insertText);
	});

	it('variable items do not get a snippet', () => {
		let text = "let count = 0;\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let item = filter(items, (i) => i.label === 'count')[0];
		assert.match(true, item.insertText === null || item.insertText === undefined);
	});
});

describe('completion — @deprecated', () => {
	beforeEach(() => dag.init(_config));

	// Full @deprecated behaviour (tags: [1] on deprecated exports) is covered
	// by e2e tests that have cross-file resolution.  Here we only verify that
	// non-deprecated scope items never carry tags.
	it('scope items for non-deprecated functions have no tags', () => {
		let text = "function greet() {}\n";
		documents.open(URI, text, 1);
		dag.add(URI, text, documents.get(URI).tree);

		let items = completion(URI, documents.get(URI), { line: 1, character: 0 });
		let item = filter(items, (i) => i.label === 'greet')[0];
		assert.match(true, item !== null);
		assert.match(true, item.tags === null || item.tags === undefined);
	});
});
