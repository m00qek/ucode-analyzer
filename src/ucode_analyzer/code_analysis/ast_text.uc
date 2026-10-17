import * as ts from 'tree_sitter';

// Comments are named nodes and may sit between any two children.
export function isComment(node) {
	let t = ts.nodeType(node);
	return t === 'comment' || t === 'doc_comment';
};

// `node`'s named children without comments.
export function namedNonComments(node) {
	return filter(ts.namedChildren(node), (c) => !isComment(c));
};

// The variable_declarators of a lexical_declaration (or a for initializer),
// without the commas and comments between them.
export function declarators(decl) {
	return filter(ts.namedChildren(decl), (c) => ts.nodeType(c) === 'variable_declarator');
};

// The first non-comment named child, for nodes without fields: parentheses,
// expression statements, `else`, spread and rest elements, `return`.
export function firstNamed(node) {
	if (!node) return null;
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let c = ts.namedChild(node, i);
		if (!isComment(c)) return c;
	}
	return null;
};

// The content of a string literal node — the concatenated text of its
// string_fragment children, without the surrounding quotes. An empty literal
// ('' / "") has no fragment child and yields "".
//
// Escape sequences are NOT decoded: a string_fragment is the raw text between
// escapes, so `"a\nb"` yields "ab" (the escape byte is dropped, not turned into
// a newline). Every caller here wants identifier-like content — module
// specifiers, member/key names — where escapes do not occur in practice.
// Escape-aware scanning (format specifiers) lives in format_string.uc.
export function stringLiteralText(node, source) {
	let out = '';
	for (let k = 0; k < ts.childCount(node); k++) {
		let ch = ts.child(node, k);
		if (ts.nodeType(ch) === 'string_fragment')
			out += ts.text(ch, source);
	}
	return out;
};

// { name → [startByte] } for every identifier (and shorthand_property_identifier)
// in the tree, built in a single pass. When skipParams is true, formal_parameters
// subtrees are skipped so an inner function's parameters don't count as uses of an
// outer name (the unused-variable pass needs that; the unused-import pass does not).
export function identifierOccurrences(root, source, skipParams) {
	let types = ['identifier', 'shorthand_property_identifier'];
	if (skipParams) push(types, 'formal_parameters');
	let idx = {};
	let skipEnd = -1;  // end of the formal_parameters being skipped
	for (let node in ts.descendants(root, types)) {
		let start = ts.startByte(node);
		if (start < skipEnd) continue;
		if (ts.nodeType(node) === 'formal_parameters') {
			skipEnd = ts.endByte(node);
			continue;
		}
		let name = ts.text(node, source);
		if (!exists(idx, name)) idx[name] = [];
		push(idx[name], start);
	}
	return idx;
};
