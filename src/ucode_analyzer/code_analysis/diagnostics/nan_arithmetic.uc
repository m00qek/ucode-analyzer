// Arithmetic that is NaN whatever runs: `-`, `*`, `/` or `%` with an operand
// that is surely not a number. ucode converts numeric strings ('5' * 2 is 10),
// so only a string literal that is not one counts, or a value inferred to be
// an array, an object or a function (`split(s, '.') - 1`).

import * as ts from 'tree_sitter';
import { stringLiteralText } from 'ucode_analyzer.code_analysis.ast_text';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

const ARITHMETIC = { '-': true, '*': true, '/': true, '%': true };

// What operand surely is that is not a number ('is an array', …), or null.
function notNumber(node, uri, doc) {
	if (ts.nodeType(node) === 'string') {
		let v = stringLiteralText(node, doc.text);
		return match(v, /^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?\s*$/) ? null : 'is not a number';
	}
	let t = inferNode(node, doc.text, uri, scopeAtOffset(doc.scopeMap, ts.startByte(node)), 0);
	if (t?.kind === 'record') return 'is an object';
	if (t?.kind === 'function') return 'is a function';
	if (t?.kind === 'generic' && t.base === 'list') return 'is an array';
	if (t?.kind === 'generic' && t.base === 'dict') return 'is an object';
	return null;
}

export function nanArithmetic(uri, doc) {
	let out = [];
	for (let n in ts.descendants(ts.rootNode(doc.tree), [ 'binary_expression' ])) {
		let op = ts.nodeType(ts.childByField(n, 'operator'));
		if (!ARITHMETIC[op]) continue;
		for (let side in [ 'left', 'right' ]) {
			let operand = ts.childByField(n, side);
			let what = operand ? notNumber(operand, uri, doc) : null;
			if (!what) continue;
			push(out, diagnostic({
				start: offsetToPosition(doc.text, doc.lineTable, ts.startByte(operand)),
				end:   offsetToPosition(doc.text, doc.lineTable, ts.endByte(operand)),
			}, Severity.WARNING, 'nan-arithmetic', sprintf("%s %s: '%s' on it is NaN",
				(ts.nodeType(operand) === 'string') ? ts.text(operand, doc.text) : "'" + ts.text(operand, doc.text) + "'", what, op)));
		}
	}
	return out;
};
