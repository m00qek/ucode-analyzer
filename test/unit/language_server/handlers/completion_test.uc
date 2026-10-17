import { describe, it, assert, beforeEach, afterEach, contains, any_order } from 'utest';
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

// The items that are not keywords: general completion always appends the
// whole keyword list, so a test checks the rest exactly.
function nonKeywords(items) {
	return filter(items, (i) => i.kind !== 14);
}

function labels(items) {
	return map(items, (i) => i.label);
}

// parser.uc's exports, in declaration order, as completion items.
let PARSER_ITEMS = [
	{ label: 'newParser', kind: 3, detail: 'object', documentation: 'Create a parser for a language.', insertText: 'newParser(${1:language})', insertTextFormat: 2 },
	{ label: 'parse', kind: 3, detail: 'object', documentation: 'Parse source text into a tree.', insertText: 'parse(${1:parser}, ${2:source})', insertTextFormat: 2 },
	{ label: 'rootNode', kind: 6, detail: null, documentation: 'The root node of a tree.' },
	{ label: 'nodeType', kind: 6, detail: null, documentation: 'The type name of a node.' },
	{ label: 'text', kind: 3, detail: 'string', documentation: 'The source text a node spans.', insertText: 'text(${1:node}, ${2:source})', insertTextFormat: 2 },
	{ label: 'parseString', kind: 3, detail: null, documentation: null, insertText: 'parseString($1)', insertTextFormat: 2, tags: [ 1 ] },
];

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

		assert.match([ { label: 'count', kind: 6, detail: 'int' } ], nonKeywords(items));
	});

	it('completion item for a variable has VARIABLE kind (6)', () => {
		let items = completeAt("let x = 5;\n$0");

		assert.match([ { label: 'x', kind: 6, detail: 'int' } ], nonKeywords(items));
	});

	it('completion item for an arrow function has FUNCTION kind (3)', () => {
		let items = completeAt("let fn = x => x;\n$0");

		assert.match([ {
			label: 'fn', kind: 3, detail: '(x: ?) => ?',
			insertText: 'fn(${1:x})', insertTextFormat: 2,
		} ], nonKeywords(items));
	});

	it('does not offer bindings declared after cursor', () => {
		// The cursor is at the start of 'let b'; buildScope uses startByte < offset,
		// so 'let b' is excluded but 'let a' (which precedes it) is included.
		let items = completeAt("let a = 1;\n$0let b = 2;\n");

		assert.match([ 'a' ], labels(nonKeywords(items)));
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
		assert.match(PARSER_ITEMS, items);
	});

	it('outside an import statement offers scope locals and named imports', () => {
		// after 'let x = 1;', so x is in scope
		let items = completeAt("import { parse } from 'parser';\nlet x = 1;\n$0");

		// the local binding and the named import
		assert.match(any_order([ 'x', 'parse' ]), labels(nonKeywords(items)));
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

		// p's exports only: neither the local x nor keywords
		assert.match(PARSER_ITEMS, items);
	});

	it('namespace import: items include the function kind for function exports', () => {
		let items = completeImporting("import * as p from 'parser';\np.$0parse");

		// KIND_FUNCTION (3) for function exports, VARIABLE (6) for the others
		assert.match([ 3, 3, 6, 6, 3, 3 ], map(items, (i) => i.kind));
	});

	it('trigger character: cursor right after dot returns members', () => {
		// 'p.' — no property typed yet
		let items = completeImporting("import * as p from 'parser';\np.$0\n");

		assert.match(PARSER_ITEMS, items);
	});

	it('record type: offers field names of an object literal', () => {
		// 'obj.foo' — obj is a local record-typed binding.
		let items = completeAt("let obj = { foo: function() {}, bar: function() {} };\nobj.$0foo");

		assert.match([
			{ label: 'foo', kind: 3, detail: '() => ?', documentation: null, insertText: 'foo()', insertTextFormat: 2 },
			{ label: 'bar', kind: 3, detail: '() => ?', documentation: null, insertText: 'bar()', insertTextFormat: 2 },
		], items);
	});

	it('record type: does not include scope locals', () => {
		let items = completeAt("let x = 99;\nlet obj = { foo: 1 };\nobj.$0foo");

		assert.match([ { label: 'foo', kind: 6, detail: 'int', documentation: null } ], items);
	});

	it('union of records: offers fields from all branches', () => {
		// x = cond ? { a: 1 } : { b: 2 }  →  union[record{a}, record{b}]
		let items = completeAt("let x = true ? { alpha: 1 } : { beta: 2 };\nx.$0a");

		assert.match(any_order([ 'alpha', 'beta' ]), labels(items));
	});

	it('union of records: deduplicates fields present in multiple branches', () => {
		// Both branches have 'shared'; result should contain it exactly once.
		let items = completeAt("let x = true ? { shared: 1, a: 2 } : { shared: 3, b: 4 };\nx.$0s");

		assert.match(any_order([ 'shared', 'a', 'b' ]), labels(items));
	});

	it('union containing non-record members: still offers record fields', () => {
		// null || { a: 1 }  →  union[null, record{a}]  (or nullable)
		// Use explicit ternary to produce a union type.
		let items = completeAt("let x = true ? null : { omega: 99 };\nx.$0o");

		assert.match([ 'omega' ], labels(items));
	});

	it('non-member position still returns general items', () => {
		// a plain identifier position, not a member expression
		let items = completeAt("import * as p from 'parser';\nlet x = 5;\n$0");

		// the local and the namespace alias (kind MODULE, 9)
		assert.match(any_order([
			{ label: 'x', kind: 6, detail: 'int' },
			{ label: 'p', kind: 9, detail: 'parser' },
		]), nonKeywords(items));
	});
});

describe('completion — keywords', () => {
	beforeEach(() => dag.init(_config));

	it('includes language keywords in general completion', () => {
		let items = completeAt("let x = 1;\n$0");
		let labels = map(items, (i) => i.label);

		// A selection of expected keywords (the full list is the handler's choice)
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

		assert.match([ { label: 'if', kind: 14 } ], filter(items, (i) => i.label === 'if'));
	});

	// Suspected bug: KEYWORDS offers these, but ucode rejects each one with a
	// syntax error (`typeof 1`, `void 0`, `[] instanceof Array`).
	it('offers ucode\'s keywords, not JavaScript\'s', () => {
		let labels = map(completeAt("let x = 1;\n$0"), (i) => i.label);
		assert.match([], filter(labels, (l) => l in [ 'do', 'finally', 'instanceof', 'throw', 'typeof', 'void' ]));
		assert.match([ 'elif', 'endfor', 'endfunction', 'endif', 'endwhile', 'this' ],
			sort(filter(labels, (l) => l in [ 'elif', 'endfor', 'endfunction', 'endif', 'endwhile', 'this' ])));
	});

	it('does not include keywords inside member expression context', () => {
		// cursor right after the dot — member context, no keywords expected
		let items = completeAt("let obj = {};\nobj.$0");

		// an empty record has no fields, and member context offers no keywords
		assert.match([], items);
	});

	it('does not include keywords inside import statement context', () => {
		// Cursor inside the module specifier string
		let items = completeAt("import { x } from '$0parser';\n");

		// the import context offers the module's exports, never keywords
		assert.match(PARSER_ITEMS, items);
	});
});

describe('completion — snippets', () => {
	beforeEach(() => dag.init(_config));

	it('function items have insertTextFormat 2 (Snippet)', () => {
		let items = completeAt("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n$0");
		assert.match([ {
			label: 'add', kind: 3, detail: '(x: int, y: int) => int',
			insertText: 'add(${1:x}, ${2:y})', insertTextFormat: 2,
		} ], nonKeywords(items));
	});

	it('snippet includes param names from JSDoc for scope items', () => {
		let items = completeAt("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\n$0");
		let item = filter(items, (i) => i.label === 'add')[0];
		assert.match('add(${1:x}, ${2:y})', item.insertText);
	});

	it('zero-param function gets empty parens snippet', () => {
		let items = completeAt("function ping() { return true; }\n$0");
		let item = filter(items, (i) => i.label === 'ping')[0];
		assert.match('ping()', item.insertText);
	});

	it('variable items do not get a snippet', () => {
		let items = completeAt("let count = 0;\n$0");
		assert.match([ { label: 'count', kind: 6, detail: 'int' } ], nonKeywords(items));
	});
});

describe('completion — @deprecated', () => {
	beforeEach(() => dag.init(_config));

	// Full @deprecated behaviour (tags: [1] on deprecated exports) is covered
	// by e2e tests that have cross-file resolution.  Here we only verify that
	// non-deprecated scope items never carry tags.
	it('scope items for non-deprecated functions have no tags', () => {
		let items = completeAt("function greet() {}\n$0");
		assert.match([ {
			label: 'greet', kind: 3, detail: '() => ?',
			insertText: 'greet()', insertTextFormat: 2,
		} ], nonKeywords(items));
	});
});
