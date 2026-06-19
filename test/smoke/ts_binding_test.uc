/*
 * Milestone 0 smoke test for bindings/ts.uc + bindings/ts_binding.c.
 *
 * Run with:
 *   ucode -L bindings test/smoke/ts_binding_test.uc
 */

import * as ts from 'ts';

function check(cond, msg) {
	if (!cond)
		die(`FAIL: ${msg}`);
}

// basic parse + node walking
let parser = ts.newParser(ts.ucode());
let src = 'let x = 5;';
let tree = ts.parse(parser, src);
let root = ts.rootNode(tree);

check(ts.nodeType(root) == 'program', `expected program, got ${ts.nodeType(root)}`);
check(ts.text(root, src) == src, 'root text should equal full source');
check(ts.namedChildCount(root) == 1, 'expected one statement');

let decl = ts.namedChild(root, 0);
check(ts.nodeType(decl) == 'lexical_declaration', `expected lexical_declaration, got ${ts.nodeType(decl)}`);
check(ts.text(decl, src) == src, 'declaration text should equal full source');
check(ts.parent(decl) != null, 'declaration should have a parent');

// collection helper
check(length(ts.namedChildren(root)) == 1, 'namedChildren() should return one statement');

// second grammar
let docParser = ts.newParser(ts.ucdocs());
let docSrc = '/** @param {string} x */';
let docTree = ts.parse(docParser, docSrc);
let docRoot = ts.rootNode(docTree);
check(ts.nodeType(docRoot) == 'document', `expected document, got ${ts.nodeType(docRoot)}`);

// node must outlive its tree/parser once a GC ref is held
function makeNode() {
	let p = ts.newParser(ts.ucode());
	let s = 'let y = 42;';
	let t = ts.parse(p, s);
	let r = ts.rootNode(t);
	return [ts.namedChild(r, 0), s];
}

let pair = makeNode();
gc();
gc();
check(ts.nodeType(pair[0]) == 'lexical_declaration', 'node should survive GC after tree/parser go out of scope');
check(ts.text(pair[0], pair[1]) == pair[1], 'node text should survive GC after tree/parser go out of scope');

// bad input raises exceptions instead of crashing
let threw = false;
try { ts.newParser('not a language'); } catch (e) { threw = true; }
check(threw, 'newParser() should reject a non-language argument');

threw = false;
try { ts.nodeType(null); } catch (e) { threw = true; }
check(threw, 'nodeType() should reject a non-node argument');

// query API: basic captures, predicate evaluation, match grouping
let qsrc = 'let x = 5, y = 6;';
let qtree = ts.parse(ts.newParser(ts.ucode()), qsrc);
let qroot = ts.rootNode(qtree);

let q1 = ts.newQuery(ts.ucode(), '(variable_declarator name: (identifier) @name)');
let caps1 = ts.queryCaptures(q1, qroot, qsrc);
check(length(caps1) == 2, `expected 2 captures, got ${length(caps1)}`);
check(ts.text(caps1[0].node, qsrc) == 'x', 'first capture should be x');
check(ts.text(caps1[1].node, qsrc) == 'y', 'second capture should be y');

let matches = ts.queryMatches(q1, qroot, qsrc);
check(length(matches) == 2, `expected 2 matches, got ${length(matches)}`);

let q2 = ts.newQuery(ts.ucode(),
	'(variable_declarator name: (identifier) @name (#not-eq? @name "y"))');
let caps2 = ts.queryCaptures(q2, qroot, qsrc);
check(length(caps2) == 1, '#not-eq? predicate should drop the "y" match');
check(ts.text(caps2[0].node, qsrc) == 'x', '#not-eq? predicate should keep the "x" match');

let q3 = ts.newQuery(ts.ucode(),
	'(variable_declarator name: (identifier) @name (#match? @name "^y$"))');
let caps3 = ts.queryCaptures(q3, qroot, qsrc);
check(length(caps3) == 1, '#match? predicate should keep only the "y" match');
check(ts.text(caps3[0].node, qsrc) == 'y', '#match? predicate should keep the "y" match');

threw = false;
try { ts.newQuery(ts.ucode(), '(this is not valid'); } catch (e) { threw = true; }
check(threw, 'newQuery() should reject invalid query syntax');

// incremental reparse: a growing edit on an earlier line must shift byte
// ranges for unaffected nodes on later lines correctly. This is the exact
// failure mode from the prototype's PROBLEMS_IN_TREESITTER.MD #4 (an
// unedited/mismatched old tree silently producing wrong byte ranges).
let rsrc1 = "let ab = 1;\nlet cd = 2;\n";
let rparser = ts.newParser(ts.ucode());
let rtree1 = ts.parse(rparser, rsrc1);

let rsrc2 = "let abcdef = 1;\nlet cd = 2;\n";
let rstart = index(rsrc1, "ab");
let roldEnd = rstart + length("ab");
let rnewEnd = rstart + length("abcdef");

let rtree2 = ts.reparse(rparser, rtree1, rsrc1, rsrc2, rstart, roldEnd, rnewEnd);
let rroot2 = ts.rootNode(rtree2);

check(ts.namedChildCount(rroot2) == 2, 'expected 2 statements after a growing reparse');
check(ts.text(ts.namedChild(rroot2, 0), rsrc2) == 'let abcdef = 1;', 'edited declaration should reflect the new text');
check(ts.text(ts.namedChild(rroot2, 1), rsrc2) == 'let cd = 2;',
	'unaffected declaration on the next line should have correctly shifted byte ranges');

// shrinking edit across a multi-line document
let rsrc3 = "let a = 1;\nlet verylongname = 2;\nlet b = 3;\n";
let rtree3 = ts.parse(rparser, rsrc3);

let rsrc4 = "let a = 1;\nlet x = 2;\nlet b = 3;\n";
let rstart2 = index(rsrc3, "verylongname");
let roldEnd2 = rstart2 + length("verylongname");
let rnewEnd2 = rstart2 + length("x");

let rtree4 = ts.reparse(rparser, rtree3, rsrc3, rsrc4, rstart2, roldEnd2, rnewEnd2);
let rroot4 = ts.rootNode(rtree4);

check(ts.namedChildCount(rroot4) == 3, `expected 3 statements after a shrinking reparse, got ${ts.namedChildCount(rroot4)}`);
check(ts.text(ts.namedChild(rroot4, 0), rsrc4) == 'let a = 1;', 'declaration before the edit should be unaffected');
check(ts.text(ts.namedChild(rroot4, 1), rsrc4) == 'let x = 2;', 'edited declaration should reflect the new text');
check(ts.text(ts.namedChild(rroot4, 2), rsrc4) == 'let b = 3;', 'declaration after the edit should have correctly shifted byte ranges');

print("ts_binding smoke test: OK\n");
