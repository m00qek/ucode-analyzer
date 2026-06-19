/*
 * Ergonomic wrapper around the native ts_native module (bindings/ts_binding.c).
 *
 * ts_binding.c is a thin, mechanical FFI layer with minimal validation.
 * This module is where argument-checking with useful error messages,
 * structured results, and collection helpers (looping over children in
 * ucode instead of C) belong.
 */

import {
	ts_language_ucode, ts_language_ucdocs,
	ts_new_parser, ts_parse, ts_root_node,
	ts_node_type, ts_node_is_named, ts_node_text,
	ts_node_start_byte, ts_node_end_byte,
	ts_node_child_count, ts_node_named_child_count,
	ts_node_child, ts_node_named_child,
	ts_node_child_by_field, ts_node_parent,
	ts_query_new, ts_query_predicate_steps, ts_query_matches
} from 'ts_native';

function expect(cond, msg) {
	if (!cond)
		die(msg);
}

export function ucode() {
	return ts_language_ucode();
}

export function ucdocs() {
	return ts_language_ucdocs();
}

export function newParser(language) {
	expect(language != null, 'newParser() expects a language handle (ts.ucode() or ts.ucdocs())');
	return ts_new_parser(language);
}

export function parse(parser, source) {
	expect(type(source) == 'string', 'parse() expects a source string');
	return ts_parse(parser, source);
}

export function rootNode(tree) {
	return ts_root_node(tree);
}

export function nodeType(node) {
	return ts_node_type(node);
}

export function isNamed(node) {
	return ts_node_is_named(node);
}

export function text(node, source) {
	expect(type(source) == 'string', 'text() expects a source string');
	return ts_node_text(node, source);
}

export function startByte(node) {
	return ts_node_start_byte(node);
}

export function endByte(node) {
	return ts_node_end_byte(node);
}

export function childCount(node) {
	return ts_node_child_count(node);
}

export function namedChildCount(node) {
	return ts_node_named_child_count(node);
}

export function child(node, i) {
	return ts_node_child(node, i);
}

export function namedChild(node, i) {
	return ts_node_named_child(node, i);
}

export function childByField(node, name) {
	expect(type(name) == 'string', 'childByField() expects a field name string');
	return ts_node_child_by_field(node, name);
}

export function parent(node) {
	return ts_node_parent(node);
}

export function children(node) {
	let result = [];

	for (let i = 0; i < childCount(node); i++)
		push(result, child(node, i));

	return result;
}

export function namedChildren(node) {
	let result = [];

	for (let i = 0; i < namedChildCount(node); i++)
		push(result, namedChild(node, i));

	return result;
}

export function newQuery(language, source) {
	expect(language != null, 'newQuery() expects a language handle (ts.ucode() or ts.ucdocs())');
	expect(type(source) == 'string', 'newQuery() expects a query source string');
	return ts_query_new(language, source);
}

/*
 * Tree-sitter's C core only hands back the raw predicate step array for a
 * pattern (capture/string steps terminated by "done" sentinels) -- it does
 * not evaluate #eq?/#match?/etc itself. This groups those steps into
 * { operator, args } predicates, where each arg is { kind: "capture"|"string", value }.
 */
function predicatesForPattern(query, patternIndex) {
	let steps = ts_query_predicate_steps(query, patternIndex);
	let predicates = [];
	let current = [];

	for (let step in steps) {
		if (step.type == 'done') {
			if (length(current) > 0) {
				push(predicates, {
					operator: current[0].value,
					args: slice(current, 1)
				});
			}

			current = [];
		}
		else {
			push(current, { kind: step.type, value: step.value });
		}
	}

	return predicates;
}

/*
 * Evaluates the standard tree-sitter query predicates (#eq?, #not-eq?,
 * #match?, #not-match?) against a match's captures. Non-standard
 * predicates used by tree-sitter-ucode's own query files (#set!, #strip!,
 * #select-adjacent!) are consumer-defined metadata, not something
 * tree-sitter (or this binding) evaluates -- see PROBLEMS_IN_TREESITTER.MD
 * in the prototype repo. They're left unevaluated here (treated as
 * always-true) so callers can inspect/apply them separately.
 */
function evalPredicate(predicate, captureMap, source) {
	function resolve(arg) {
		if (arg.kind == 'capture') {
			let node = captureMap[arg.value];
			return node ? text(node, source) : null;
		}

		return arg.value;
	}

	switch (predicate.operator) {
		case 'eq?':
			return resolve(predicate.args[0]) == resolve(predicate.args[1]);

		case 'not-eq?':
			return resolve(predicate.args[0]) != resolve(predicate.args[1]);

		case 'match?':
			return match(resolve(predicate.args[0]), regexp(predicate.args[1].value)) != null;

		case 'not-match?':
			return match(resolve(predicate.args[0]), regexp(predicate.args[1].value)) == null;

		default:
			return true;
	}
}

/*
 * Runs a query against a node, evaluates standard predicates per pattern,
 * and returns the matches that pass: [{ pattern, captures: [{ name, node }] }].
 * Matches failing a standard predicate are dropped; non-standard predicates
 * (#set!, #strip!, ...) are passed through unevaluated -- see evalPredicate().
 */
export function queryMatches(query, node, source) {
	expect(type(source) == 'string', 'queryMatches() expects a source string');

	let raw = ts_query_matches(query, node);
	let result = [];

	for (let m in raw) {
		let captureMap = {};

		for (let c in m.captures)
			captureMap[c.name] = c.node;

		let ok = true;

		for (let p in predicatesForPattern(query, m.pattern)) {
			if (!evalPredicate(p, captureMap, source)) {
				ok = false;
				break;
			}
		}

		if (ok)
			push(result, m);
	}

	return result;
}

/* Flat [{ name, node }] across all (predicate-filtered) matches. */
export function queryCaptures(query, node, source) {
	let result = [];

	for (let m in queryMatches(query, node, source))
		for (let c in m.captures)
			push(result, c);

	return result;
}
