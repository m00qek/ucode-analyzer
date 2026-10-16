import * as ts from 'tree_sitter';
import { scopeGet, scopeSet } from 'code_analysis.types.scope';
import { UNKNOWN, NULL_T, STR, INT, FLOAT, BOOL, resolveRef } from 'code_analysis.types.type_utils';
import { stringLiteralText, firstNamed, namedNonComments } from 'code_analysis.ast_text';

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
	type = resolveRef(type);
	if (type.kind === 'nullable') return type.inner;
	if (type.kind === 'primitive' && type.name === 'null') return UNKNOWN;
	if (type.kind === 'union') {
		let kept = [];
		for (let i = 0; i < length(type.members); i++) {
			let m = type.members[i];
			// A member may itself be nullable (`c ? match(…) : null`).
			if (m.kind === 'nullable') m = m.inner;
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
	type = resolveRef(type);
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

// A direct string/number literal node's concrete value (mirrors the inferrer's
// literalValueOf), or null when the node isn't a plain literal.
function literalNodeValue(node, source) {
	if (!node) return null;
	let nt = ts.nodeType(node);
	if (nt === 'string')
		return stringLiteralText(node, source);
	if (nt === 'number') {
		let v = +ts.text(node, source);
		if (type(v) === 'int' || type(v) === 'double') return v;
	}
	return null;
}

// How a single record variant relates to `field === value`:
//   'match'    — its `field` is a literal equal to value
//   'no-match' — its `field` is a literal NOT equal to value
//   'unknown'  — `field` is absent or not a literal (can't decide → keep in both)
function discriminantState(record, field, value) {
	if (!record || record.kind !== 'record') return 'unknown';
	let ft = null;
	for (let i = 0; i < length(record.fields); i++)
		if (record.fields[i].name === field) { ft = record.fields[i].type; break; }
	if (!ft || ft.kind !== 'primitive' || !exists(ft, 'value')) return 'unknown';
	return ft.value === value ? 'match' : 'no-match';
}

// Refine a union of record variants by a discriminant test `name.field === value`.
// keep=true  (true branch): drop variants that definitely don't match.
// keep=false (false branch): drop the variant that definitely does match.
// Variants whose discriminant is unknown survive both branches (sound). Non-union
// inputs, or a partition that removes nothing/everything, are returned unchanged.
export function narrowUnionByDiscriminant(type, field, value, keep) {
	type = resolveRef(type);
	if (type.kind !== 'union') return type;
	let kept = [];
	for (let i = 0; i < length(type.members); i++) {
		let state = discriminantState(resolveRef(type.members[i]), field, value);
		let drop = keep ? (state === 'no-match') : (state === 'match');
		if (!drop) push(kept, type.members[i]);
	}
	if (length(kept) === 0 || length(kept) === length(type.members)) return type;
	if (length(kept) === 1) return kept[0];
	return { kind: 'union', members: kept };
};

// Guards are typed objects describing what a condition asserts about a variable:
//
//   { kind: 'truthy', name, positive }
//       Truthy/falsy check or null equality: if(x), if(!x), x!==null, x===null.
//       positive=true means the condition asserts x is truthy/non-null.
//
//   { kind: 'type', name, positive, toType }
//       type(x) === 'string' (positive=true) or !== (positive=false).
//
//   { kind: 'variant', name, field, value, positive }
//       Discriminant test r.field === <literal> (positive=true) or !==. Refines
//       a tagged union bound to `name` to the matching variant(s) per branch.
//
//   { kind: 'and', guards }
//       Compound &&: all sub-guards hold in the consequent; alternate is
//       ambiguous (we can't tell which sub-condition failed), so applyGuard
//       skips narrowing for positive=false.
//
//   { kind: 'or', guards }
//       Compound ||, the mirror image: every sub-guard fails in the alternate
//       (`if (!m || bad(m)) return;` leaves m non-null after it); the
//       consequent is ambiguous.

export function parseGuard(node, source) {
	if (!node) return null;
	let nt = ts.nodeType(node);

	if (nt === 'parenthesized_expression')
		return parseGuard(firstNamed(node), source);

	if (nt === 'identifier')
		return { kind: 'truthy', name: ts.text(node, source), positive: true };

	if (nt === 'unary_expression') {
		if (ts.nodeType(ts.childByField(node, 'operator')) === '!') {
			let operand = ts.childByField(node, 'argument');
			if (operand && ts.nodeType(operand) === 'identifier')
				return { kind: 'truthy', name: ts.text(operand, source), positive: false };
		}
		return null;
	}

	if (nt === 'binary_expression') {
		let op = ts.nodeType(ts.childByField(node, 'operator'));

		if (op === '&&' || op === '||') {
			// In the consequent all sub-conditions hold; collect guards and apply
			// each positively. In the alternate we can't tell which sub-condition
			// failed, so we wrap in a compound guard that applyGuard skips when
			// positive=false, giving safe/conservative behaviour.
			let left  = ts.childByField(node, 'left');
			let right = ts.childByField(node, 'right');
			let leftGuard  = left  ? parseGuard(left,  source) : null;
			let rightGuard = right ? parseGuard(right, source) : null;
			if (!leftGuard && !rightGuard) return null;
			let guards = [];
			if (leftGuard)  push(guards, leftGuard);
			if (rightGuard) push(guards, rightGuard);
			return { kind: op === '&&' ? 'and' : 'or', guards };
		}

		let isNotEq = (op === '!==' || op === '!=');
		let isEq    = (op === '===' || op === '==');
		if (!isNotEq && !isEq) return null;

		let left  = ts.childByField(node, 'left');
		let right = ts.childByField(node, 'right');
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
			    && args && length(namedNonComments(args)) === 1) {
				let operand = firstNamed(args);
				if (operand && ts.nodeType(operand) === 'identifier') {
					let name    = ts.text(operand, source);
					let raw     = ts.text(stringSide, source);
					let typeStr = replace(raw, /^['"]|['"]$/g, '');
					let toType  = TYPE_FUNC_MAP[typeStr];
					if (toType)
						return { kind: 'type', name, positive: isEq, toType };
					// object/array/function have no singleton type, but
					// `type(x) === '<non-null kind>'` still proves x is non-null in
					// the true branch (type(null) is 'null'). Narrow only that
					// branch — wrapping in an 'and' guard makes applyGuard skip the
					// false branch, where x could still be null.
					if (isEq)
						return { kind: 'and', guards: [ { kind: 'truthy', name, positive: true } ] };
				}
			}
		}

		// r.kind === 'fail'  /  r.kind !== 'fail'  — discriminant test on a
		// tagged union: one side is `identifier.field`, the other a literal.
		let memberSide = null, litSide = null;
		if (ts.nodeType(left) === 'member_expression') { memberSide = left; litSide = right; }
		else if (ts.nodeType(right) === 'member_expression') { memberSide = right; litSide = left; }
		if (memberSide) {
			let objNode  = ts.childByField(memberSide, 'object');
			let propNode = ts.childByField(memberSide, 'property');
			if (objNode  && ts.nodeType(objNode)  === 'identifier' &&
			    propNode && ts.nodeType(propNode) === 'property_identifier') {
				let lv = literalNodeValue(litSide, source);
				if (lv !== null)
					return {
						kind: 'variant',
						name:  ts.text(objNode,  source),
						field: ts.text(propNode, source),
						value: lv,
						positive: isEq,
					};
			}
		}

		// x !== null  /  x === null
		let varNode = null;
		if (ts.nodeType(right) === 'null' && ts.nodeType(left) === 'identifier')
			varNode = left;
		else if (ts.nodeType(left) === 'null' && ts.nodeType(right) === 'identifier')
			varNode = right;
		if (!varNode) return null;

		return { kind: 'truthy', name: ts.text(varNode, source), positive: isNotEq };
	}

	return null;
};

export function applyGuard(scope, guard, positive) {
	if (!guard) return;
	if (guard.kind === 'and' || guard.kind === 'or') {
		// `and` holds every sub-guard when true, `or` fails every one when
		// false; the other branch is ambiguous.
		if (positive === (guard.kind === 'and'))
			for (let i = 0; i < length(guard.guards); i++)
				applyGuard(scope, guard.guards[i], positive);
		return;
	}
	let current = scopeGet(scope, guard.name);
	let inTrueBranch = guard.positive ? positive : !positive;
	if (guard.kind === 'variant') {
		scopeSet(scope, guard.name,
			narrowUnionByDiscriminant(current ?? UNKNOWN, guard.field, guard.value, inTrueBranch));
	} else if (guard.kind === 'type') {
		scopeSet(scope, guard.name, inTrueBranch
			? guard.toType
			: narrowExcluding(current ?? UNKNOWN, guard.toType));
	} else {
		// kind === 'truthy'
		scopeSet(scope, guard.name, inTrueBranch ? narrowToNonNull(current ?? UNKNOWN) : NULL_T);
	}
};
