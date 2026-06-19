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
	ts_node_child_by_field, ts_node_parent
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
