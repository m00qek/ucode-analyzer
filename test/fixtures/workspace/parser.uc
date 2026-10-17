// A small library for the tests to import, read and navigate: stable, unlike
// the analyzer's own sources. Shaped like a parser binding: documented
// functions, and constants bound to function values.

/**
 * Create a parser for a language.
 * @param {string} language - The language name.
 * @returns {object}
 */
export function newParser(language) {
	return { language };
};

/**
 * Parse source text into a tree.
 * @param {object} parser - A parser from newParser().
 * @param {string} source - The text to parse.
 * @returns {object}
 */
export function parse(parser, source) {
	return { parser, source, root: { type: 'program', children: [] } };
};

/** The root node of a tree. */
export const rootNode = (tree) => tree.root;

/** The type name of a node. */
export const nodeType = (node) => node.type;

/**
 * The source text a node spans.
 * @param {object} node
 * @param {string} source
 * @returns {string}
 */
export function text(node, source) {
	return substr(source, node.start, node.end - node.start);
};

/** @deprecated Use parse() instead. */
export function parseString(source) {
	return parse(newParser('ucode'), source);
};
