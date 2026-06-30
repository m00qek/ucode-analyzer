import * as ts from 'tree_sitter';
import { scopeGet, scopeSet } from 'language_server.types.scope';
import { UNKNOWN, NULL_T, STR, INT, FLOAT, BOOL } from 'language_server.types.type_utils';

// Maps the strings returned by ucode's type() built-in to our type objects.
// Covers the primitive/scalar types we can represent as singletons; array,
// object, and function types are omitted (no clean singleton exists for them).
let TYPE_FUNC_MAP = {
    'null':   NULL_T,
    'int':    INT,
    'bool':   BOOL,
    'string': STR,
    'double': FLOAT,
};

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

// Remove a specific type from a union.  Used for the negative branch of a
// typeof guard: if (typeof x !== 'string') → in the else, x is not string.
// For non-union types we leave the type unchanged (can't compute complement).
function narrowExcluding(type, exclude) {
	if (type.kind !== 'union') return type;
	let kept = [];
	for (let i = 0; i < length(type.members); i++) {
		let m = type.members[i];
		if (m.kind === exclude.kind && m.kind === 'primitive' && m.name === exclude.name) continue;
		push(kept, m);
	}
	if (length(kept) === 0) return UNKNOWN;
	if (length(kept) === 1) return kept[0];
	return { kind: 'union', members: kept };
}

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

		if (op === '&&') {
			// In the consequent all sub-conditions hold; collect guards and apply
			// each positively. In the alternate we can't tell which sub-condition
			// failed, so we wrap in a compound guard that applyGuard skips when
			// positive=false, giving safe/conservative behaviour.
			let left  = ts.namedChild(node, 0);
			let right = ts.namedChild(node, 1);
			let leftGuard  = left  ? parseGuard(left,  source) : null;
			let rightGuard = right ? parseGuard(right, source) : null;
			if (!leftGuard && !rightGuard) return null;
			let guards = [];
			if (leftGuard)  push(guards, leftGuard);
			if (rightGuard) push(guards, rightGuard);
			return { compound: '&&', guards };
		}

		let isNotEq = (op === '!==' || op === '!=');
		let isEq    = (op === '===' || op === '==');
		if (!isNotEq && !isEq) return null;

		let left  = ts.namedChild(node, 0);
		let right = ts.namedChild(node, 1);
		if (!left || !right) return null;

		// type(x) === "string"  /  "string" === type(x)  (and !== variants)
		// type() is the ucode built-in that returns a type-name string.
		let callSide   = null;
		let stringSide = null;
		if (ts.nodeType(left) === 'call_expression' && ts.nodeType(right) === 'string') {
			callSide = left; stringSide = right;
		} else if (ts.nodeType(right) === 'call_expression' && ts.nodeType(left) === 'string') {
			callSide = right; stringSide = left;
		}
		if (callSide) {
			let callee = ts.childByField(callSide, 'function');
			let args   = ts.childByField(callSide, 'arguments');
			if (callee && ts.nodeType(callee) === 'identifier' && ts.text(callee, source) === 'type'
			    && args && ts.namedChildCount(args) === 1) {
				let operand = ts.namedChild(args, 0);
				if (operand && ts.nodeType(operand) === 'identifier') {
					let raw     = ts.text(stringSide, source);
					let typeStr = replace(raw, /^['"]|['"]$/g, '');
					let toType  = TYPE_FUNC_MAP[typeStr];
					if (toType)
						return { name: ts.text(operand, source), positive: isEq, toType };
				}
			}
		}

		// x !== null  /  x === null
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
	if (guard.compound === '&&') {
		// All sub-guards hold in the true branch; false branch is ambiguous.
		if (positive)
			for (let i = 0; i < length(guard.guards); i++)
				applyGuard(scope, guard.guards[i], true);
		return;
	}
	let current = scopeGet(scope, guard.name);
	let inTrueBranch = guard.positive ? positive : !positive;
	if (guard.toType) {
		scopeSet(scope, guard.name, inTrueBranch
			? guard.toType
			: narrowExcluding(current ?? UNKNOWN, guard.toType));
	} else {
		scopeSet(scope, guard.name, inTrueBranch ? narrowToNonNull(current ?? UNKNOWN) : NULL_T);
	}
};
