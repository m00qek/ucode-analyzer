import * as ts from 'tree_sitter';
import { scopeGet, scopeSet } from 'language_server.types.scope';
import { UNKNOWN, NULL_T } from 'language_server.types.type_utils';

export function narrowToNonNull(type) {
	if (!type || type.kind === 'unknown') return UNKNOWN;
	if (type.kind === 'nullable') return type.inner;
	if (type.kind === 'primitive' && type.name === 'null') return UNKNOWN;
	if (type.kind === 'union') {
		let kept = [];
		for (let i = 0; i < length(type.members); i++) {
			let m = type.members[i];
			if (!(m.kind === 'primitive' && m.name === 'null')) push(kept, m);
		}
		if (length(kept) === 0) return UNKNOWN;
		if (length(kept) === 1) return kept[0];
		return { kind: 'union', members: kept };
	}
	return type;
};

export function parseGuard(node, source) {
	if (!node) return null;
	let nt = ts.nodeType(node);

	if (nt === 'parenthesized_expression')
		return parseGuard(ts.namedChild(node, 0), source);

	if (nt === 'identifier')
		return { name: ts.text(node, source), positive: true };

	if (nt === 'unary_expression') {
		if (ts.nodeType(ts.child(node, 0)) === '!') {
			let operand = ts.namedChild(node, 0);
			if (operand && ts.nodeType(operand) === 'identifier')
				return { name: ts.text(operand, source), positive: false };
		}
		return null;
	}

	if (nt === 'binary_expression') {
		let op = ts.nodeType(ts.child(node, 1));
		let isNotEq = (op === '!==' || op === '!=');
		let isEq    = (op === '===' || op === '==');
		if (!isNotEq && !isEq) return null;

		let left  = ts.namedChild(node, 0);
		let right = ts.namedChild(node, 1);
		if (!left || !right) return null;

		let varNode = null;
		if (ts.nodeType(right) === 'null' && ts.nodeType(left) === 'identifier')
			varNode = left;
		else if (ts.nodeType(left) === 'null' && ts.nodeType(right) === 'identifier')
			varNode = right;
		if (!varNode) return null;

		return { name: ts.text(varNode, source), positive: isNotEq };
	}

	return null;
};

export function applyGuard(scope, guard, positive) {
	if (!guard) return;
	let current = scopeGet(scope, guard.name);
	let inTrueBranch = guard.positive ? positive : !positive;
	scopeSet(scope, guard.name, inTrueBranch ? narrowToNonNull(current ?? UNKNOWN) : NULL_T);
};
