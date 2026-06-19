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

print("ts_binding smoke test: OK\n");
