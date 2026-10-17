import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';

let SEVERITY_WARNING = 2;

// Terminator statement types: once one of these appears in a block, all
// subsequent siblings in the same block are unreachable.
let TERMINATORS = {
	return_statement:   true,
	break_statement:    true,
	continue_statement: true,
};

// Report the statements after a terminator in one block. Returns the byte
// range they and the terminator cover, which the caller skips; or null.
function checkBlock(node, source, lineTable, out) {
	let terminator = null;
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let stmt = ts.namedChild(node, i);
		// Comments are extra nodes, not code: a trailing `return x; // note`
		// must not be reported as unreachable, and a comment never terminates
		// or revives a block.
		let st = ts.nodeType(stmt);
		if (st === 'comment' || st === 'doc_comment')
			continue;
		if (terminator) {
			push(out, {
				range:    rangeOf(source, lineTable, stmt),
				severity: SEVERITY_WARNING,
				source:   'ucode-analyzer',
				code:     'unreachable-code',
				message:  'Unreachable code',
			});
		} else if (TERMINATORS[st]) {
			terminator = stmt;
		}
	}
	return terminator ? [ts.startByte(terminator), ts.endByte(node)] : null;
}

export function unreachableCode(doc) {
	let diags   = [];
	// Blocks inside a flagged statement are not reported again: their parent
	// statement already is. The skipped ranges nest, innermost on top.
	let skipped = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), ['statement_block', 'statement_list'])) {
		let start = ts.startByte(node);
		while (length(skipped) && skipped[-1][1] <= start) pop(skipped);
		if (length(skipped) && skipped[-1][0] <= start) continue;
		let range = checkBlock(node, doc.text, doc.lineTable, diags);
		if (range) push(skipped, range);
	}
	return diags;
};
