/*
 * Milestone 0 smoke test for bindings/ucode/ts_binding.c.
 *
 * Run with:
 *   ucode -L bindings/ucode/build test/smoke/ts_binding_test.uc
 */

import {
	ts_new_parser, ts_parse, ts_root_node,
	ts_node_type, ts_node_text, ts_node_is_named,
	ts_node_child_count, ts_node_named_child_count,
	ts_node_child, ts_node_named_child, ts_node_parent,
	ts_language_ucode, ts_language_ucdocs
} from 'ts';

function check(cond, msg) {
	if (!cond)
		die(`FAIL: ${msg}`);
}

// basic parse + node walking
let parser = ts_new_parser(ts_language_ucode());
let src = 'let x = 5;';
let tree = ts_parse(parser, src);
let root = ts_root_node(tree);

check(ts_node_type(root) == 'program', `expected program, got ${ts_node_type(root)}`);
check(ts_node_text(root, src) == src, 'root text should equal full source');
check(ts_node_named_child_count(root) == 1, 'expected one statement');

let decl = ts_node_named_child(root, 0);
check(ts_node_type(decl) == 'lexical_declaration', `expected lexical_declaration, got ${ts_node_type(decl)}`);
check(ts_node_text(decl, src) == src, 'declaration text should equal full source');
check(ts_node_parent(decl) != null, 'declaration should have a parent');

// second grammar
let docParser = ts_new_parser(ts_language_ucdocs());
let docSrc = '/** @param {string} x */';
let docTree = ts_parse(docParser, docSrc);
let docRoot = ts_root_node(docTree);
check(ts_node_type(docRoot) == 'document', `expected document, got ${ts_node_type(docRoot)}`);

// node must outlive its tree/parser once a GC ref is held
function makeNode() {
	let p = ts_new_parser(ts_language_ucode());
	let s = 'let y = 42;';
	let t = ts_parse(p, s);
	let r = ts_root_node(t);
	return [ts_node_named_child(r, 0), s];
}

let pair = makeNode();
gc();
gc();
check(ts_node_type(pair[0]) == 'lexical_declaration', 'node should survive GC after tree/parser go out of scope');
check(ts_node_text(pair[0], pair[1]) == pair[1], 'node text should survive GC after tree/parser go out of scope');

// bad input raises exceptions instead of crashing
let threw = false;
try { ts_new_parser('not a language'); } catch (e) { threw = true; }
check(threw, 'ts_new_parser should reject a non-language argument');

threw = false;
try { ts_node_type(null); } catch (e) { threw = true; }
check(threw, 'ts_node_type should reject a non-node argument');

print("ts_binding smoke test: OK\n");
