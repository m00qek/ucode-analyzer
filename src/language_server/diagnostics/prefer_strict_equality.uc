import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';

let SEVERITY_HINT = 4;

function collect(node, source, lineTable, out) {
	if (ts.nodeType(node) === 'binary_expression') {
		let op     = ts.child(node, 1);
		let opType = op ? ts.nodeType(op) : null;
		if (opType === '==' || opType === '!=') {
			let strict = (opType === '==') ? '===' : '!==';
			push(out, {
				range:    rangeOf(source, lineTable, op),
				severity: SEVERITY_HINT,
				message:  sprintf("Prefer '%s' over '%s'", strict, opType),
			});
		}
	}
	for (let i = 0; i < ts.namedChildCount(node); i++)
		collect(ts.namedChild(node, i), source, lineTable, out);
}

export function preferStrictEquality(doc) {
	let lineTable = buildLineTable(doc.text);
	let diags     = [];
	collect(ts.rootNode(doc.tree), doc.text, lineTable, diags);
	return diags;
};
