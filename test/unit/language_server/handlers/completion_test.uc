import { describe, it, assert, beforeEach, afterEach, contains, not } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { completion } from 'ucode_analyzer.language_server.handlers.completion';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI        = 'file:///test.uc';
let PARSER_URI = fixture.uri('parser.uc');

let _config = fixture.config();

// Open the marked text, add it to the DAG and complete at $0.
function completeAt(marked) {
	let src = cursors(marked);
	documents.open(URI, src.text, 1);
	dag.add(URI, src.text, documents.get(URI).tree);
	return completion(URI, documents.get(URI), src.at[0]);
}

// The same, building the scope map only once the DAG has the imports.
function completeImporting(marked) {
	let src = cursors(marked);
	dag.add(URI, src.text, documents.open(URI, src.text, 1).tree);
	return completion(URI, documents.get(URI), src.at[0]);
}

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(PARSER_URI);
	invalidateUri(URI);
});

describe('completion — scope', () => {
	beforeEach(() => dag.init(_config));

	it('offers local let binding at cursor', () => {
		let items = completeAt("let count = 0;\n$0");

		let labels = map(items, (i) => i.label);
		assert.match(contains(['count']), labels);
	});

	it('completion item for a variable has VARIABLE kind (6)', () => {
		let items = completeAt("let x = 5;\n$0");
		let item = null;
		for (let i in items) if (i.label === 'x') { item = i; break; }

		if (item === null) die('expected a completion item for x');
		assert.match(6, item.kind);
	});

	it('completion item for an arrow function has FUNCTION kind (3)', () => {
		let items = completeAt("let fn = x => x;\n$0");
		let item = null;
		for (let i in items) if (i.label === 'fn') { item = i; break; }

		if (item === null) die('expected a completion item for fn');
		assert.match(3, item.kind);
	});

	it('does not offer bindings declared after cursor', () => {
		// The cursor is at the start of 'let b'; buildScope uses startByte < offset,
		// so 'let b' is excluded but 'let a' (which precedes it) is included.
		let items = completeAt("let a = 1;\n$0let b = 2;\n");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['a']), labels);
		assert.match(not(contains(['b'])), labels);
	});
});

describe('completion — import context', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(PARSER_URI);  // populate the parser exports
	});

	it('inside an import statement returns exports of the target module', () => {
		let items = completeAt("import { p$0arse } from 'parser';\n");

		// Falling through to importedItems would return only {parse}, so the
		// other exports distinguish the two paths.
		assert.match(contains(['newParser', 'parse', 'rootNode', 'nodeType', 'text', 'parseString']), map(items, (i) => i.label));
	});

	it('outside an import statement offers scope locals and named imports', () => {
		// after 'let x = 1;', so x is in scope
		let items = completeAt("import { parse } from 'parser';\nlet x = 1;\n$0");

		let labels = map(items, (i) => i.label);
		assert.match(contains(['x']), labels);      // local binding
		assert.match(contains(['parse']), labels);  // named import
	});
});

describe('completion — member (cursor on property)', () => {
	beforeEach(() => {
		dag.init(_config);
		dag.addFromDisk(PARSER_URI);
	});

	it('namespace import: offers exports of the module, not all scope items', () => {
		// Cursor on 'parse' in 'p.parse' — should return p members only.
		let items = completeImporting("import * as p from 'parser';\nlet x = 5;\np.$0parse");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['parse']), labels);   // p export
		assert.match(not(contains(['x'])), labels);      // local binding — must NOT appear
	});

	it('namespace import: items include the function kind for function exports', () => {
		let items = completeImporting("import * as p from 'parser';\np.$0parse");
		let item = null;
		for (let i in items) if (i.label === 'parse') { item = i; break; }

		if (item === null) die('expected a completion item for parse');
		assert.match(3, item.kind);  // KIND_FUNCTION
	});

	it('trigger character: cursor right after dot returns members', () => {
		// 'p.' — no property typed yet
		let items = completeImporting("import * as p from 'parser';\np.$0\n");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['parse']), labels);
	});

	it('record type: offers field names of an object literal', () => {
		// 'obj.foo' — obj is a local record-typed binding.
		let items = completeAt("let obj = { foo: function() {}, bar: function() {} };\nobj.$0foo");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['foo']), labels);
		assert.match(contains(['bar']), labels);
	});

	it('record type: does not include scope locals', () => {
		let items = completeAt("let x = 99;\nlet obj = { foo: 1 };\nobj.$0foo");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['foo']), labels);
		assert.match(not(contains(['x'])), labels);
	});

	it('union of records: offers fields from all branches', () => {
		// x = cond ? { a: 1 } : { b: 2 }  →  union[record{a}, record{b}]
		let items = completeAt("let x = true ? { alpha: 1 } : { beta: 2 };\nx.$0a");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['alpha']), labels);
		assert.match(contains(['beta']), labels);
	});

	it('union of records: deduplicates fields present in multiple branches', () => {
		// Both branches have 'shared'; result should contain it exactly once.
		let items = completeAt("let x = true ? { shared: 1, a: 2 } : { shared: 3, b: 4 };\nx.$0s");
		let labels = map(items, (i) => i.label);

		let count = 0;
		for (let l in labels) if (l === 'shared') count++;
		assert.match(1, count);
		assert.match(contains(['a']), labels);
		assert.match(contains(['b']), labels);
	});

	it('union containing non-record members: still offers record fields', () => {
		// null || { a: 1 }  →  union[null, record{a}]  (or nullable)
		// Use explicit ternary to produce a union type.
		let items = completeAt("let x = true ? null : { omega: 99 };\nx.$0o");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['omega']), labels);
	});

	it('non-member position still returns general items', () => {
		// a plain identifier position, not a member expression
		let items = completeAt("import * as p from 'parser';\nlet x = 5;\n$0");
		let labels = map(items, (i) => i.label);

		assert.match(contains(['x']), labels);
		assert.match(contains(['p']), labels);  // namespace alias is in scope
	});
});

describe('completion — keywords', () => {
	beforeEach(() => dag.init(_config));

	it('includes language keywords in general completion', () => {
		let items = completeAt("let x = 1;\n$0");
		let labels = map(items, (i) => i.label);

		// A selection of expected keywords
		assert.match(contains(['if']), labels);
		assert.match(contains(['for']), labels);
		assert.match(contains(['while']), labels);
		assert.match(contains(['return']), labels);
		assert.match(contains(['let']), labels);
		assert.match(contains(['function']), labels);
		assert.match(contains(['true']), labels);
		assert.match(contains(['null']), labels);
	});

	it('keyword items have KEYWORD kind (14)', () => {
		let items = completeAt("let x = 1;\n$0");
		let ifItem = null;
		for (let i in items) if (i.label === 'if') { ifItem = i; break; }

		if (ifItem === null) die('expected a completion item for if');
		assert.match(14, ifItem.kind);
	});

	it('does not include keywords inside member expression context', () => {
		// cursor right after the dot — member context, no keywords expected
		let items = completeAt("let obj = {};\nobj.$0");
		let labels = map(items, (i) => i.label);

		assert.match(not(contains(['if'])), labels);
		assert.match(not(contains(['return'])), labels);
	});

	it('does not include keywords inside import statement context', () => {
		// Cursor inside the module specifier string
		let items = completeAt("import { x } from '$0parser';\n");
		let labels = map(items, (i) => i.label);

		assert.match(not(contains(['if'])), labels);
	});
});

describe('completion — snippets', () => {
	beforeEach(() => dag.init(_config));

	it('function items have insertTextFormat 2 (Snippet)', () => {
		let items = completeAt("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n$0");
		let item = filter(items, (i) => i.label === 'add')[0];
		assert.match(true, item !== null);
		assert.match(2, item.insertTextFormat);
	});

	it('snippet includes param names from JSDoc for scope items', () => {
		let items = completeAt("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n$0");
		let item = filter(items, (i) => i.label === 'add')[0];
		assert.match(contains('x'), item.insertText);
		assert.match(contains('y'), item.insertText);
		assert.match('add(${1:x}, ${2:y})', item.insertText);
	});

	it('zero-param function gets empty parens snippet', () => {
		let items = completeAt("function ping() { return true; }\n$0");
		let item = filter(items, (i) => i.label === 'ping')[0];
		assert.match('ping()', item.insertText);
	});

	it('variable items do not get a snippet', () => {
		let items = completeAt("let count = 0;\n$0");
		let item = filter(items, (i) => i.label === 'count')[0];
		assert.match(true, item.insertText === null);
	});
});

describe('completion — @deprecated', () => {
	beforeEach(() => dag.init(_config));

	// Full @deprecated behaviour (tags: [1] on deprecated exports) is covered
	// by e2e tests that have cross-file resolution.  Here we only verify that
	// non-deprecated scope items never carry tags.
	it('scope items for non-deprecated functions have no tags', () => {
		let items = completeAt("function greet() {}\n$0");
		let item = filter(items, (i) => i.label === 'greet')[0];
		assert.match(true, item !== null);
		assert.match(true, item.tags === null);
	});
});
