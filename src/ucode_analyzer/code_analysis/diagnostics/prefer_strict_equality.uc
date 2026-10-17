import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

export function preferStrictEquality(doc) {
	let diags = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), ['binary_expression'])) {
		let op     = ts.child(node, 1);
		let opType = op ? ts.nodeType(op) : null;
		if (opType === '==' || opType === '!=') {
			let strict = (opType === '==') ? '===' : '!==';
			push(diags, diagnostic(rangeOf(doc.text, doc.lineTable, op), Severity.HINT, 'prefer-strict-equality',
				sprintf("Prefer '%s' over '%s'", strict, opType)));
		}
	}
	return diags;
};
