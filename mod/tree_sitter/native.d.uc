/**
 * # tree_sitter.native
 *
 * Thin, mechanical FFI layer over the tree-sitter C library. Implemented in
 * `mod/tree_sitter/native.c`, installed as
 * `/usr/lib/ucode/tree_sitter/native.so`. Imported as
 * `import * as native from 'tree_sitter.native'`.
 *
 * Prefer the ergonomic `tree_sitter` wrapper (`src/tree_sitter.uc`) over calling
 * these directly — the wrapper adds argument validation and structured results.
 * Handles (language, parser, tree, node, query) are opaque native resources.
 */

/** @typedef {any} Language - Opaque tree-sitter language handle. */
/** @typedef {any} Parser - Opaque parser instance. */
/** @typedef {any} Tree - Parsed syntax tree; node handles go stale after ts_reparse. */
/** @typedef {any} Node - Immutable handle to a single syntax node. */
/** @typedef {any} Query - Compiled tree-sitter query. */

// ── Language handles ────────────────────────────────────────────────────────

/** Return the language handle for the ucode grammar. @returns {Language} */
export function ts_language_ucode() {};

/** Return the language handle for the ucdocs grammar. @returns {Language} */
export function ts_language_ucdocs() {};

// ── Parser lifecycle ────────────────────────────────────────────────────────

/**
 * Create a parser configured for `language`.
 * @param {Language} language
 * @returns {Parser}
 */
export function ts_new_parser(language) {};

/**
 * Parse `source` from scratch and return a new tree.
 * @param {Parser} parser
 * @param {string} source
 * @returns {Tree}
 */
export function ts_parse(parser, source) {};

/**
 * Incrementally reparse `oldTree` after a single byte-range edit.
 * @param {Parser} parser
 * @param {Tree} oldTree
 * @param {object} edit - Byte/point offsets of the replaced range.
 * @param {string} newSource
 * @returns {Tree}
 */
export function ts_reparse(parser, oldTree, edit, newSource) {};

// ── Node accessors ──────────────────────────────────────────────────────────

/** @param {Tree} tree @returns {Node} */
export function ts_root_node(tree) {};

/** @param {Node} node @returns {string} Grammar node type name. */
export function ts_node_type(node) {};

/** @param {Node} node @returns {boolean} True for named (non-anonymous) nodes. */
export function ts_node_is_named(node) {};

/**
 * @param {Node} node
 * @param {string} source - The source string passed to ts_parse.
 * @returns {string} The source text the node spans.
 */
export function ts_node_text(node, source) {};

/** @param {Node} node @returns {int} Start byte offset. */
export function ts_node_start_byte(node) {};

/** @param {Node} node @returns {int} End byte offset (exclusive). */
export function ts_node_end_byte(node) {};

/** @param {Node} node @returns {int} Number of children (named + anonymous). */
export function ts_node_child_count(node) {};

/** @param {Node} node @returns {int} Number of named children. */
export function ts_node_named_child_count(node) {};

/** @param {Node} node @param {int} index @returns {?Node} i-th child (0-based). */
export function ts_node_child(node, index) {};

/** @param {Node} node @param {int} index @returns {?Node} i-th named child (0-based). */
export function ts_node_named_child(node, index) {};

/**
 * @param {Node} node
 * @param {string} name - Grammar field name (e.g. 'name', 'value', 'body').
 * @returns {?Node} First child with the given field, or null.
 */
export function ts_node_child_by_field(node, name) {};

/** @param {Node} node @returns {?Node} Parent node, or null at the root. */
export function ts_node_parent(node) {};

// ── Query API ───────────────────────────────────────────────────────────────

/**
 * Compile a query pattern string. Throws on a syntax error in `source`.
 * @param {Language} language
 * @param {string} source - Tree-sitter query syntax.
 * @returns {Query}
 */
export function ts_query_new(language, source) {};

/** @param {Query} query @returns {int} Number of patterns in the query. */
export function ts_query_pattern_count(query) {};

/**
 * Raw predicate steps for one pattern (capture/string steps with "done"
 * sentinels); evaluation is done in the wrapper.
 * @param {Query} query
 * @param {int} patternIndex
 * @returns {object[]} Steps of the form { type, value }.
 */
export function ts_query_predicate_steps(query, patternIndex) {};

/**
 * Run `query` over the subtree rooted at `node`.
 * @param {Query} query
 * @param {Node} node
 * @returns {object[]} Matches of the form { pattern, captures: [{ name, node }] }.
 */
export function ts_query_matches(query, node) {};
