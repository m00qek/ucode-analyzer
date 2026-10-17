import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import * as native from 'tree_sitter.native';

describe('ts (node/tree lifecycle)', () => {
	it('parses and walks a tree', () => {
		let parser = ts.newParser(ts.ucode());
		let src = 'let x = 5;';
		let tree = ts.parse(parser, src);
		let root = ts.rootNode(tree);

		assert.match('program', ts.nodeType(root));
		assert.match(src, ts.text(root, src));
		assert.match(1, ts.namedChildCount(root));

		let decl = ts.namedChild(root, 0);
		assert.match('lexical_declaration', ts.nodeType(decl));
		assert.match(src, ts.text(decl, src));
		assert.match('program', ts.nodeType(ts.parent(decl)));
		assert.match(src, ts.text(ts.parent(decl), src));
	});

	it('namedChildren() collects all named children', () => {
		let tree = ts.parse(ts.newParser(ts.ucode()), 'let x = 5;');
		assert.match(['lexical_declaration'], map(ts.namedChildren(ts.rootNode(tree)), ts.nodeType));
	});

	it('parses the ucdocs grammar too', () => {
		let tree = ts.parse(ts.newParser(ts.ucdocs()), '/** @param {string} x */');
		assert.match('document', ts.nodeType(ts.rootNode(tree)));
	});

	it('keeps a node valid after its tree/parser go out of scope and GC runs', () => {
		function makeNode() {
			let t = ts.parse(ts.newParser(ts.ucode()), 'let y = 42;');
			return [ts.namedChild(ts.rootNode(t), 0), 'let y = 42;'];
		}

		let pair = makeNode();
		gc();
		gc();

		assert.match('lexical_declaration', ts.nodeType(pair[0]));
		assert.match(pair[1], ts.text(pair[0], pair[1]));
	});

	it('isNamed() distinguishes named nodes from anonymous tokens', () => {
		let src = 'let x = 5;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let decl = ts.namedChild(ts.rootNode(tree), 0);  // lexical_declaration

		// child(0) is the anonymous 'let' keyword token
		assert.match(false, ts.isNamed(ts.child(decl, 0)));
		// namedChild(0) is the variable_declarator (named)
		assert.match(true, ts.isNamed(ts.namedChild(decl, 0)));
	});

	it('startByte() and endByte() span the correct byte range', () => {
		let src = 'let x = 5;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let varDecl = ts.namedChild(ts.namedChild(ts.rootNode(tree), 0), 0);  // variable_declarator
		let ident = ts.childByField(varDecl, 'name');  // identifier 'x'

		assert.match(4, ts.startByte(ident));  // 'let ' = 4 bytes
		assert.match(5, ts.endByte(ident));    // 'x' is 1 byte
		assert.match('x', ts.text(ident, src));
	});

	it('childCount() includes anonymous tokens; namedChildCount() does not', () => {
		let src = 'let x = 5;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let decl = ts.namedChild(ts.rootNode(tree), 0);  // lexical_declaration: 'let' + variable_declarator + ';'

		assert.match(3, ts.childCount(decl));
		assert.match(1, ts.namedChildCount(decl));
	});

	it('child() returns anonymous token at index 0; namedChild() skips it', () => {
		let src = 'let x = 5;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let decl = ts.namedChild(ts.rootNode(tree), 0);  // lexical_declaration

		assert.match('let', ts.nodeType(ts.child(decl, 0)));
		assert.match('variable_declarator', ts.nodeType(ts.namedChild(decl, 0)));
	});

	it('children() and namedChildren() lengths match childCount() / namedChildCount()', () => {
		let src = 'let x = 5, y = 6;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let decl = ts.namedChild(ts.rootNode(tree), 0);  // lexical_declaration

		assert.match(ts.childCount(decl), length(ts.children(decl)));
		assert.match(ts.namedChildCount(decl), length(ts.namedChildren(decl)));
	});

	it('childByField() returns the field node; null for unknown field', () => {
		let src = 'let x = 5;';
		let tree = ts.parse(ts.newParser(ts.ucode()), src);
		let varDecl = ts.namedChild(ts.namedChild(ts.rootNode(tree), 0), 0);  // variable_declarator

		let nameNode = ts.childByField(varDecl, 'name');
		assert.match('identifier', ts.nodeType(nameNode));
		assert.match('x', ts.text(nameNode, src));
		assert.match(null, ts.childByField(varDecl, 'no_such_field'));
	});

	it('parent() returns null for the root node', () => {
		let tree = ts.parse(ts.newParser(ts.ucode()), 'let x = 5;');
		assert.match(null, ts.parent(ts.rootNode(tree)));
	});

	it('rejects a non-language argument to newParser()', () => {
		assert.throws(() => { ts.newParser('not a language'); });
	});

	it('rejects a non-node argument to nodeType()', () => {
		assert.throws(() => { ts.nodeType(null); });
	});

	it('rejects a non-string source argument to text()', () => {
		let tree = ts.parse(ts.newParser(ts.ucode()), 'let x = 5;');
		assert.throws(() => { ts.text(ts.rootNode(tree), 42); });
	});

	it('rejects a non-string field name in childByField()', () => {
		let tree = ts.parse(ts.newParser(ts.ucode()), 'let x = 5;');
		let varDecl = ts.namedChild(ts.namedChild(ts.rootNode(tree), 0), 0);
		assert.throws(() => { ts.childByField(varDecl, 99); });
	});
});

describe('ts (child lists and descendant lookup)', () => {
	let src = "/** d */\nfunction f(a, ...b) {\n\tlet x = a?.b[0] + 1; // c\n\treturn `t${x}`;\n}\n";
	let root = ts.rootNode(ts.parse(ts.newParser(ts.ucode()), src));

	// Reference implementations: the index loops the native calls replace.
	function loopChildren(n, named) {
		let out = [];
		let count = named ? ts.namedChildCount(n) : ts.childCount(n);
		for (let i = 0; i < count; i++) push(out, named ? ts.namedChild(n, i) : ts.child(n, i));
		return out;
	}
	function sig(nodes) { return map(nodes, (n) => sprintf('%s@%d-%d', ts.nodeType(n), ts.startByte(n), ts.endByte(n))); }
	function eachNode(n, fn) { fn(n); for (let c in loopChildren(n, false)) eachNode(c, fn); }
	function refNamedAt(n, off) {
		for (let c in loopChildren(n, true))
			if (ts.startByte(c) <= off && off < ts.endByte(c)) return refNamedAt(c, off);
		return n;
	}
	function refAt(n, off) {
		for (let c in loopChildren(n, false))
			if (ts.startByte(c) <= off && off < ts.endByte(c)) return refAt(c, off);
		return n;
	}

	it('children and namedChildren match the index loops on every node', () => {
		eachNode(root, (n) => {
			assert.match(sig(loopChildren(n, false)), sig(ts.children(n)));
			assert.match(sig(loopChildren(n, true)), sig(ts.namedChildren(n)));
		});
	});

	it('namedDescendantAt and descendantAt match a descent by offset at every byte', () => {
		for (let off = 0; off <= length(src); off++) {
			assert.match(sig([refNamedAt(root, off)]), sig([ts.namedDescendantAt(root, off)]));
			assert.match(sig([refAt(root, off)]), sig([ts.descendantAt(root, off)]));
		}
	});

	it('descendantOffsets lists the starts of matching descendants in order', () => {
		let want = [];
		eachNode(root, (n) => {
			let t = ts.nodeType(n);
			if (t === 'identifier' || t === 'statement_block') push(want, ts.startByte(n));
		});
		assert.match(want, ts.descendantOffsets(root, ['identifier', 'statement_block']));
		assert.match([], ts.descendantOffsets(root, ['no_such_type']));
		let fn = ts.namedChild(root, 1);
		assert.match([ts.startByte(fn)], ts.descendantOffsets(fn, ['function_declaration']));
	});

	it('descendants lists the matching descendants in order', () => {
		let want = [];
		eachNode(root, (n) => {
			let t = ts.nodeType(n);
			if (t === 'identifier' || t === 'statement_block') push(want, [t, ts.startByte(n)]);
		});
		let got = map(ts.descendants(root, ['identifier', 'statement_block']),
			(n) => [ts.nodeType(n), ts.startByte(n)]);
		assert.match(want, got);
		assert.match([], ts.descendants(root, ['no_such_type']));
		let fn = ts.namedChild(root, 1);
		assert.match([ts.startByte(fn)], map(ts.descendants(fn, ['function_declaration']), ts.startByte));
	});

	it('childrenByField returns the named children under a field', () => {
		let d = "/** @type {Map<string, int>} */";
		let droot = ts.rootNode(ts.parse(ts.newParser(ts.ucdocs()), d));
		let named = ts.namedChild(ts.namedChild(ts.namedChild(droot, 0), 0), 0);
		assert.match('named_type', ts.nodeType(named));
		assert.match(['primitive_type', 'primitive_type'], map(ts.childrenByField(named, 'params'), ts.nodeType));
		assert.match([], ts.childrenByField(named, 'no_such_field'));
	});
});

describe('ts (query API)', () => {
	it('rejects a pattern index out of range', () => {
		let q = ts.newQuery(ts.ucode(), '(identifier) @id');
		assert.match([], native.ts_query_predicate_steps(q, 0));
		assert.throws(() => native.ts_query_predicate_steps(q, 1));
		assert.throws(() => native.ts_query_predicate_steps(q, -1));
	});

	function declarations(src) {
		return ts.rootNode(ts.parse(ts.newParser(ts.ucode()), src));
	}

	it('captures matches with no predicate', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(), '(variable_declarator name: (identifier) @name)');

		let caps = ts.queryCaptures(query, root, src);
		assert.match([['name', 'x'], ['name', 'y']], map(caps, (c) => [c.name, ts.text(c.node, src)]));

		// one match per declarator, each with its one capture
		let matches = ts.queryMatches(query, root, src);
		assert.match([[0, [['name', 'x']]], [0, [['name', 'y']]]], map(matches, (m) =>
			[m.pattern, map(m.captures, (c) => [c.name, ts.text(c.node, src)])]));
	});

	it('patternCount() returns the number of patterns in a query', () => {
		let q1 = ts.newQuery(ts.ucode(), '(identifier) @id');
		assert.match(1, ts.patternCount(q1));

		// alternation counts as 2 separate patterns
		let q2 = ts.newQuery(ts.ucode(), '(identifier) @id\n(number) @num');
		assert.match(2, ts.patternCount(q2));
	});

	it('filters matches with #eq?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#eq? @name "x"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(['x'], map(caps, (c) => ts.text(c.node, src)));
	});

	it('filters matches with #not-eq?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#not-eq? @name "y"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(['x'], map(caps, (c) => ts.text(c.node, src)));
	});

	it('filters matches with #match?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#match? @name "^y$"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(['y'], map(caps, (c) => ts.text(c.node, src)));
	});

	it('filters matches with #not-match?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#not-match? @name "^y$"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(['x'], map(caps, (c) => ts.text(c.node, src)));
	});

	it('rejects invalid query syntax', () => {
		assert.throws(() => { ts.newQuery(ts.ucode(), '(this is not valid'); });
	});

	it('rejects a non-language argument to newQuery()', () => {
		assert.throws(() => { ts.newQuery(null, '(identifier) @id'); });
	});
});

describe('ts (incremental reparse)', () => {
	// This is the exact failure mode from the prototype's
	// PROBLEMS_IN_TREESITTER.MD #4 (an unedited/mismatched old tree
	// silently producing wrong byte ranges) -- a growing/shrinking edit on
	// an earlier line must shift byte ranges for unaffected later nodes
	// correctly.

	it('shifts byte ranges correctly after a growing edit', () => {
		let parser = ts.newParser(ts.ucode());
		let src1 = "let ab = 1;\nlet cd = 2;\n";
		let tree1 = ts.parse(parser, src1);

		let src2 = "let abcdef = 1;\nlet cd = 2;\n";
		let start = index(src1, 'ab');
		let oldEnd = start + length('ab');
		let newEnd = start + length('abcdef');

		let tree2 = ts.reparse(parser, tree1, src1, src2, start, oldEnd, newEnd);
		let root2 = ts.rootNode(tree2);

		assert.match(2, ts.namedChildCount(root2));
		assert.match('let abcdef = 1;', ts.text(ts.namedChild(root2, 0), src2));
		assert.match('let cd = 2;', ts.text(ts.namedChild(root2, 1), src2));
	});

	it('shifts byte ranges correctly after a shrinking edit', () => {
		let parser = ts.newParser(ts.ucode());
		let src1 = "let a = 1;\nlet verylongname = 2;\nlet b = 3;\n";
		let tree1 = ts.parse(parser, src1);

		let src2 = "let a = 1;\nlet x = 2;\nlet b = 3;\n";
		let start = index(src1, 'verylongname');
		let oldEnd = start + length('verylongname');
		let newEnd = start + length('x');

		let tree2 = ts.reparse(parser, tree1, src1, src2, start, oldEnd, newEnd);
		let root2 = ts.rootNode(tree2);

		assert.match(3, ts.namedChildCount(root2));
		assert.match('let a = 1;', ts.text(ts.namedChild(root2, 0), src2));
		assert.match('let x = 2;', ts.text(ts.namedChild(root2, 1), src2));
		assert.match('let b = 3;', ts.text(ts.namedChild(root2, 2), src2));
	});

	it('rejects a non-string old source argument', () => {
		let parser = ts.newParser(ts.ucode());
		let src = 'let x = 1;';
		let tree = ts.parse(parser, src);
		assert.throws(() => { ts.reparse(parser, tree, 42, src, 0, 0, 0); });
	});

	it('rejects a non-string new source argument', () => {
		let parser = ts.newParser(ts.ucode());
		let src = 'let x = 1;';
		let tree = ts.parse(parser, src);
		assert.throws(() => { ts.reparse(parser, tree, src, 42, 0, 0, 0); });
	});
});
