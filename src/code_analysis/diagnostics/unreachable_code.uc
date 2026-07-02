import * as ts from 'tree_sitter';
import { rangeOf } from 'code_analysis.positions';

let SEVERITY_WARNING = 2;

// Terminator statement types: once one of these appears in a block, all
// subsequent siblings in the same block are unreachable.
let TERMINATORS = {
	return_statement:   true,
	break_statement:    true,
	continue_statement: true,
};

function walk(node, source, lineTable, out) {
	let nt = ts.nodeType(node);

	if (nt === 'statement_block') {
		let hitTerminator = false;
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let stmt = ts.namedChild(node, i);
			// Comments are extra nodes, not code: a trailing `return x; // note`
			// must not be reported as unreachable, and a comment never terminates
			// or revives a block. Skip without touching hitTerminator.
			if (ts.nodeType(stmt) === 'comment')
				continue;
			if (hitTerminator) {
				push(out, {
					range:    rangeOf(source, lineTable, stmt),
					severity: SEVERITY_WARNING,
					source:   'ucode-ls',
					code:     'unreachable-code',
					message:  'Unreachable code',
				});
				// Still recurse so we don't hide nested terminators, but skip
				// emitting for inner blocks — their parent statement is already flagged.
				continue;
			}
			if (TERMINATORS[ts.nodeType(stmt)]) {
				hitTerminator = true;
			} else {
				walk(stmt, source, lineTable, out);
			}
		}
		return;
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, out);
}

export function unreachableCode(doc) {
	let lineTable = doc.lineTable;
	let diags     = [];
	walk(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	return diags;
};
