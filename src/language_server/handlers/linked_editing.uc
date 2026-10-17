import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition } from 'code_analysis.positions';

// Colon-form blocks rename their keyword pair together: `for` and the `for`
// of `endfor` are one linked range, so retyping `for` as `while` also turns
// `endfor` into `endwhile`. An if with elif/else is left out (a rename would
// break its clauses), as is a missing (zero-width) closer.

const OPENERS = { 'if': true, 'for': true, 'while': true, 'function': true };
const BLOCKS = {
	if_alt_statement: true, for_alt_statement: true, for_in_alt_statement: true,
	while_alt_statement: true, function_declaration: true,
};

// The opening and closing keyword tokens of a colon-form block, or null.
function keywordPair(node) {
	if (!BLOCKS[ts.nodeType(node)]) return null;
	let kids = ts.children(node);
	let open = null, close = null;
	for (let c in kids)
		if (!ts.isNamed(c) && OPENERS[ts.nodeType(c)]) { open = c; break; }
	let last = kids[-1];
	if (!open || !last || ts.isNamed(last) || ts.isMissing(last)) return null;
	if (ts.nodeType(last) !== 'end' + ts.nodeType(open)) return null;
	if (ts.nodeType(node) === 'if_alt_statement' &&
	    (ts.childByField(node, 'alternative') || length(filter(ts.namedChildren(node), (c) => ts.nodeType(c) === 'elif_clause'))))
		return null;
	return { open, close: last };
}

export function linkedEditingRanges(doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root = ts.rootNode(doc.tree);
	for (let n = ts.descendantAt(root, offset); n; n = ts.parent(n)) {
		let pair = keywordPair(n);
		if (!pair) continue;
		let onOpen  = ts.startByte(pair.open) <= offset && offset <= ts.endByte(pair.open);
		let onClose = ts.startByte(pair.close) <= offset && offset <= ts.endByte(pair.close);
		if (!onOpen && !onClose) return null;   // inside the block, not on its keywords
		let pos = (o) => offsetToPosition(doc.text, doc.lineTable, o);
		return {
			ranges: [
				{ start: pos(ts.startByte(pair.open)),     end: pos(ts.endByte(pair.open)) },
				{ start: pos(ts.startByte(pair.close) + 3), end: pos(ts.endByte(pair.close)) },
			],
			wordPattern: '[a-z]+',
		};
	}
	return null;
};
