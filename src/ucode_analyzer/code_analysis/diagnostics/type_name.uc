// A comparison of type()'s result with a name it never returns:
// `type(x) == 'integer'` is always false (the name is 'int'), and so is
// `type(x) == 'null'`, for type(null) is null itself. Literal names only, so
// it cannot misfire.

import * as ts from 'tree_sitter';
import { stringLiteralText, firstNamed } from 'ucode_analyzer.code_analysis.ast_text';
import { scopeHas, isRootBinding } from 'ucode_analyzer.code_analysis.types.scope';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

// What type() returns, for every value but null.
const NAMES = { int: true, double: true, bool: true, string: true, array: true, object: true,
	function: true, regexp: true, resource: true };

// The names other languages (and ucdocs) use for them.
const MEANT = { integer: 'int', float: 'double', number: 'int', boolean: 'bool', list: 'array',
	dict: 'object', table: 'object', map: 'object' };

const EQUALITY = { '==': true, '!=': true, '===': true, '!==': true };

// True when node calls the builtin type() (not a local of that name).
function isTypeCall(node, doc) {
	if (!node || ts.nodeType(node) !== 'call_expression') return false;
	let callee = ts.childByField(node, 'function');
	if (!callee || ts.nodeType(callee) !== 'identifier' || ts.text(callee, doc.text) !== 'type') return false;
	let scope = scopeAtOffset(doc.scopeMap, ts.startByte(node));
	return !scopeHas(scope, 'type') || isRootBinding(scope, 'type');
}

function check(lit, doc, out) {
	if (!lit || ts.nodeType(lit) !== 'string') return;
	let name = stringLiteralText(lit, doc.text);
	if (NAMES[name]) return;
	let message = (name === 'null')
		? "type() never returns 'null': for null it returns null itself, so compare with null"
		: MEANT[name]
			? sprintf("type() never returns '%s': did you mean '%s'?", name, MEANT[name])
			: sprintf("type() never returns '%s'", name);
	push(out, diagnostic({
		start: offsetToPosition(doc.text, doc.lineTable, ts.startByte(lit)),
		end:   offsetToPosition(doc.text, doc.lineTable, ts.endByte(lit)),
	}, Severity.WARNING, 'impossible-type-check', message));
}

export function typeNameChecks(doc) {
	let out = [];
	for (let n in ts.descendants(ts.rootNode(doc.tree), [ 'binary_expression', 'switch_statement' ])) {
		if (ts.nodeType(n) === 'binary_expression') {
			if (!EQUALITY[ts.nodeType(ts.childByField(n, 'operator'))]) continue;
			let l = ts.childByField(n, 'left'), r = ts.childByField(n, 'right');
			if (isTypeCall(l, doc)) check(r, doc, out);
			else if (isTypeCall(r, doc)) check(l, doc, out);
			continue;
		}
		let wrap = ts.childByField(n, 'value');
		let body = ts.childByField(n, 'body');
		if (!body || !isTypeCall(firstNamed(wrap) ?? wrap, doc)) continue;
		for (let c in ts.namedChildren(body))
			if (ts.nodeType(c) === 'switch_case') check(ts.childByField(c, 'value'), doc, out);
	}
	return out;
};
