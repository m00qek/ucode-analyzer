import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';

let SEVERITY_HINT = 4;

export function preferStrictEquality(doc) {
	let diags = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), ['binary_expression'])) {
		let op     = ts.child(node, 1);
		let opType = op ? ts.nodeType(op) : null;
		if (opType === '==' || opType === '!=') {
			let strict = (opType === '==') ? '===' : '!==';
			push(diags, {
				range:    rangeOf(doc.text, doc.lineTable, op),
				severity: SEVERITY_HINT,
				source:   'ucode-analyzer',
				code:     'prefer-strict-equality',
				message:  sprintf("Prefer '%s' over '%s'", strict, opType),
			});
		}
	}
	return diags;
};
