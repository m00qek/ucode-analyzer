import { describe, it, assert } from 'utest';
import * as ts from 'ucode_language_server.ts';

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
		assert.match(true, ts.parent(decl) != null);
	});

	it('namedChildren() collects all named children', () => {
		let tree = ts.parse(ts.newParser(ts.ucode()), 'let x = 5;');
		assert.match(1, length(ts.namedChildren(ts.rootNode(tree))));
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

	it('rejects a non-language argument to newParser()', () => {
		assert.throws(() => { ts.newParser('not a language'); });
	});

	it('rejects a non-node argument to nodeType()', () => {
		assert.throws(() => { ts.nodeType(null); });
	});
});

describe('ts (query API)', () => {
	function declarations(src) {
		return ts.rootNode(ts.parse(ts.newParser(ts.ucode()), src));
	}

	it('captures matches with no predicate', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(), '(variable_declarator name: (identifier) @name)');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(2, length(caps));
		assert.match('x', ts.text(caps[0].node, src));
		assert.match('y', ts.text(caps[1].node, src));

		let matches = ts.queryMatches(query, root, src);
		assert.match(2, length(matches));
	});

	it('filters matches with #not-eq?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#not-eq? @name "y"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(1, length(caps));
		assert.match('x', ts.text(caps[0].node, src));
	});

	it('filters matches with #match?', () => {
		let src = 'let x = 5, y = 6;';
		let root = declarations(src);
		let query = ts.newQuery(ts.ucode(),
			'(variable_declarator name: (identifier) @name (#match? @name "^y$"))');

		let caps = ts.queryCaptures(query, root, src);
		assert.match(1, length(caps));
		assert.match('y', ts.text(caps[0].node, src));
	});

	it('rejects invalid query syntax', () => {
		assert.throws(() => { ts.newQuery(ts.ucode(), '(this is not valid'); });
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
});
