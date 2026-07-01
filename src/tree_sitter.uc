/*
 * Ergonomic wrapper around the native module (mod/tree_sitter/native.c).
 *
 * mod/native.c is a thin, mechanical FFI layer with minimal validation.
 * This module is where argument-checking with useful error messages,
 * structured results, and collection helpers (looping over children in
 * ucode instead of C) belong. Pure native pass-throughs are re-exported
 * as const; only functions that add validation or logic are wrapped.
 */

import * as native from 'tree_sitter.native';

function expect(cond, msg) {
	if (!cond)
		die(msg);
}

/* tree-sitter points are (row, column), both 0-based, column in bytes. */
function pointAt(source, byteOffset) {
	let row = 0;
	let lastNewline = -1;

	for (let i = 0; i < byteOffset; i++) {
		if (substr(source, i, 1) === "\n") {
			row++;
			lastNewline = i;
		}
	}

	return { row: row, column: byteOffset - lastNewline - 1 };
}

// ── Opaque handle types ───────────────────────────────────────────────────

/** @typedef {any} Language — Opaque tree-sitter language handle returned by ts.ucode(), ts.ucdocs() or ts.markup(). */
/** @typedef {any} Parser — Opaque parser instance created by ts.newParser(). */
/** @typedef {any} Tree — Parsed syntax tree. All node handles become stale after ts.reparse(). */
/** @typedef {any} Node — Immutable handle to a single syntax node within a Tree. */
/** @typedef {any} Query — Compiled tree-sitter query pattern object. */

/** @typedef {{ name: string, node: Node }} QueryCapture — A named capture from a query match. */
/** @typedef {{ pattern: int, captures: QueryCapture[] }} QueryMatch — A single match produced by ts.queryMatches(). */

// ── Language handles ──────────────────────────────────────────────────────

/**
 * Return the tree-sitter language handle for the ucode grammar.
 * @returns {Language}
 */
export const ucode = native.ts_language_ucode;

/**
 * Return the tree-sitter language handle for the ucdocs grammar.
 * @returns {Language}
 */
export const ucdocs = native.ts_language_ucdocs;

/**
 * Return the tree-sitter language handle for the ucode template-mode
 * ('ucode_markup') grammar — files written as text with embedded {% %} / {{ }}
 * / {# #} tags. The code inside tags uses the same node types as ts.ucode().
 * @returns {Language}
 */
export const markup = native.ts_language_ucode_markup;

// ── Parser lifecycle ──────────────────────────────────────────────────────

/**
 * Create a new parser configured for the given language.
 * @param {Language} language — result of ts.ucode(), ts.ucdocs() or ts.markup()
 * @returns {Parser}
 */
export function newParser(language) {
	expect(language !== null, 'newParser() expects a language handle (ts.ucode(), ts.ucdocs() or ts.markup())');
	return native.ts_new_parser(language);
};

/**
 * Parse source text from scratch and return a new syntax tree.
 * @param {Parser} parser
 * @param {string} source
 * @returns {Tree}
 */
export function parse(parser, source) {
	expect(type(source) === 'string', 'parse() expects a source string');
	return native.ts_parse(parser, source);
};

/**
 * Incrementally reparse oldTree to reflect a single contiguous byte-range
 * replacement and return the new tree.
 *
 * oldTree must be the tree produced by the immediately preceding parse of
 * oldSource. Passing a mismatched tree produces a structurally valid but
 * silently wrong result. All node handles obtained from oldTree become stale
 * the moment this function returns; fetch fresh nodes from the returned tree.
 *
 * startByte/oldEndByte describe the byte range in oldSource that was replaced;
 * newEndByte is where that range ends in newSource after the replacement
 * (i.e. startByte + byte-length of the replacement text).
 *
 * @param {Parser} parser
 * @param {Tree} oldTree
 * @param {string} oldSource
 * @param {string} newSource
 * @param {int} startByte
 * @param {int} oldEndByte
 * @param {int} newEndByte
 * @returns {Tree}
 */
export function reparse(parser, oldTree, oldSource, newSource, startByte, oldEndByte, newEndByte) {
	expect(type(oldSource) === 'string', 'reparse() expects an old source string');
	expect(type(newSource) === 'string', 'reparse() expects a new source string');

	let startPoint = pointAt(oldSource, startByte);
	let oldEndPoint = pointAt(oldSource, oldEndByte);
	let newEndPoint = pointAt(newSource, newEndByte);

	let edit = {
		startByte: startByte,
		oldEndByte: oldEndByte,
		newEndByte: newEndByte,
		startRow: startPoint.row,
		startColumn: startPoint.column,
		oldEndRow: oldEndPoint.row,
		oldEndColumn: oldEndPoint.column,
		newEndRow: newEndPoint.row,
		newEndColumn: newEndPoint.column,
	};

	return native.ts_reparse(parser, oldTree, edit, newSource);
};

// ── Tree / node accessors ─────────────────────────────────────────────────

/**
 * Return the root node of a parsed syntax tree.
 * @param {Tree} tree
 * @returns {Node}
 */
export const rootNode = native.ts_root_node;

/**
 * Return the grammar node type name of a node (e.g. 'identifier', 'string').
 * @param {Node} node
 * @returns {string}
 */
export const nodeType = native.ts_node_type;

/**
 * Return true if node is a named node (as opposed to an anonymous token).
 * @param {Node} node
 * @returns {boolean}
 */
export const isNamed = native.ts_node_is_named;

/**
 * Return the source text that node spans.
 * @param {Node} node
 * @param {string} source — the same source string passed to ts.parse()
 * @returns {string}
 */
export function text(node, source) {
	expect(type(source) === 'string', 'text() expects a source string');
	return native.ts_node_text(node, source);
};

/**
 * Return the byte offset of the start of node in the source.
 * @param {Node} node
 * @returns {int}
 */
export const startByte = native.ts_node_start_byte;

/**
 * Return the byte offset of the end of node in the source (exclusive).
 * @param {Node} node
 * @returns {int}
 */
export const endByte = native.ts_node_end_byte;

/**
 * Return the total number of children of node (named and anonymous).
 * @param {Node} node
 * @returns {int}
 */
export const childCount = native.ts_node_child_count;

/**
 * Return the number of named children of node.
 * @param {Node} node
 * @returns {int}
 */
export const namedChildCount = native.ts_node_named_child_count;

/**
 * Return the i-th child of node (named and anonymous, 0-based).
 * @param {Node} node
 * @param {int} index
 * @returns {?Node}
 */
export const child = native.ts_node_child;

/**
 * Return the i-th named child of node (0-based).
 * @param {Node} node
 * @param {int} index
 * @returns {?Node}
 */
export const namedChild = native.ts_node_named_child;

/**
 * Return the first child of node with the given field name, or null.
 * Field names are grammar-defined (e.g. 'name', 'value', 'body').
 * @param {Node} node
 * @param {string} name — field name
 * @returns {?Node}
 */
export function childByField(node, name) {
	expect(type(name) === 'string', 'childByField() expects a field name string');
	return native.ts_node_child_by_field(node, name);
};

/**
 * Return the parent node of node, or null if node is the root.
 * @param {Node} node
 * @returns {?Node}
 */
export const parent = native.ts_node_parent;

/**
 * Return all children of node (named and anonymous) as an array.
 * @param {Node} node
 * @returns {Node[]}
 */
export function children(node) {
	let result = [];

	for (let i = 0; i < childCount(node); i++)
		push(result, child(node, i));

	return result;
};

/**
 * Return only the named children of node as an array.
 * @param {Node} node
 * @returns {Node[]}
 */
export function namedChildren(node) {
	let result = [];

	for (let i = 0; i < namedChildCount(node); i++)
		push(result, namedChild(node, i));

	return result;
};

// ── Query API ─────────────────────────────────────────────────────────────

/**
 * Compile a tree-sitter query pattern string for the given language.
 * Throws on syntax error in source.
 * @param {Language} language — result of ts.ucode() or ts.ucdocs()
 * @param {string} source — tree-sitter query syntax
 * @returns {Query}
 */
export function newQuery(language, source) {
	expect(language !== null, 'newQuery() expects a language handle (ts.ucode() or ts.ucdocs())');
	expect(type(source) === 'string', 'newQuery() expects a query source string');
	return native.ts_query_new(language, source);
};

/**
 * Return the number of patterns in a compiled query.
 * @param {Query} query
 * @returns {int}
 */
export const patternCount = native.ts_query_pattern_count;

/*
 * Tree-sitter's C core only hands back the raw predicate step array for a
 * pattern (capture/string steps terminated by "done" sentinels) -- it does
 * not evaluate #eq?/#match?/etc itself. This groups those steps into
 * { operator, args } predicates, where each arg is { kind: "capture"|"string", value }.
 */
function predicatesForPattern(query, patternIndex) {
	let steps = native.ts_query_predicate_steps(query, patternIndex);
	let predicates = [];
	let current = [];

	for (let step in steps) {
		if (step.type === 'done') {
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
		if (arg.kind === 'capture') {
			let node = captureMap[arg.value];
			return node ? text(node, source) : null;
		}

		return arg.value;
	}

	switch (predicate.operator) {
		case 'eq?':
			return resolve(predicate.args[0]) === resolve(predicate.args[1]);

		case 'not-eq?':
			return resolve(predicate.args[0]) !== resolve(predicate.args[1]);

		case 'match?':
			return match(resolve(predicate.args[0]), regexp(predicate.args[1].value)) !== null;

		case 'not-match?':
			return match(resolve(predicate.args[0]), regexp(predicate.args[1].value)) === null;

		default:
			return true;
	}
}

/**
 * Run query against node, evaluate standard predicates per pattern, and
 * return the matches that pass all predicates.
 *
 * Non-standard predicates (#set!, #strip!, #select-adjacent!) are treated
 * as always-true and passed through in the raw captures for callers to
 * handle separately.
 *
 * @param {Query} query
 * @param {Node} node — root of the subtree to search
 * @param {string} source — the source string passed to ts.parse()
 * @returns {QueryMatch[]}
 */
export function queryMatches(query, node, source) {
	expect(type(source) === 'string', 'queryMatches() expects a source string');

	let raw = native.ts_query_matches(query, node);
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
};

/**
 * Return all captures across all predicate-filtered matches as a flat array.
 * Equivalent to flattening the captures arrays from ts.queryMatches().
 * @param {Query} query
 * @param {Node} node — root of the subtree to search
 * @param {string} source — the source string passed to ts.parse()
 * @returns {QueryCapture[]}
 */
export function queryCaptures(query, node, source) {
	let result = [];

	for (let m in queryMatches(query, node, source))
		for (let c in m.captures)
			push(result, c);

	return result;
};
