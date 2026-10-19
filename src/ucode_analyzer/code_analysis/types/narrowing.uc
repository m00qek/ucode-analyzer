import * as ts from 'tree_sitter';
import { scopeGet, scopeSet } from 'ucode_analyzer.code_analysis.types.scope';
import { UNKNOWN, NULL_T, STR, INT, FLOAT, BOOL, resolveRef, unionOf } from 'ucode_analyzer.code_analysis.types.type_utils';
import { stringLiteralText, firstNamed, namedNonComments } from 'ucode_analyzer.code_analysis.ast_text';

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

// type() names whose values have shapes of their own (KINDS[name] when
// nothing more is known): where `type(x) == name` holds, x keeps only those of
// its types, and where it fails, it loses them. regexp and resource values
// have none here, and a handle's typedef is kept in both branches: the
// declarations type handles as records, though type() says 'resource'.
const KINDS = {
	object:   { kind: 'generic', base: 'dict', params: [ UNKNOWN ] },
	array:    { kind: 'generic', base: 'list', params: [ UNKNOWN ] },
	function: { kind: 'function', params: [], return: UNKNOWN },
};

// Whether t's values have type() name `name`: true, false, or null when it
// cannot tell.
// JSDoc's builtin names, which stay opaque refs (doc_parser), by type() name.
const OPAQUE_KINDS = { object: 'object', array: 'array', regexp: 'regexp', resource: 'resource',
	integer: 'int', double: 'double', number: 'int' };

function ofKind(t, name) {
	let k = t.kind;
	if (k === 'ref') return OPAQUE_KINDS[t.name] ? OPAQUE_KINDS[t.name] === name : null;
	if (k === 'record') return name === 'object';
	if (k === 'generic') return name === ((t.base === 'list') ? 'array' : 'object');
	if (k === 'function') return name === 'function';
	if (k === 'primitive') return false;
	return null;
}

// t's alternatives, a nullable's null among them.
function alternatives(t) {
	if (t.kind === 'nullable') return [ ...alternatives(t.inner), NULL_T ];
	if (t.kind === 'union') {
		let out = [];
		for (let m in t.members) push(out, ...alternatives(m));
		return out;
	}
	return [ t ];
}

// x's type t where `type(x) == name` holds, or fails.
function narrowKind(t, name, holds) {
	if (!t || t.kind === 'unknown' || t.kind === 'any') return holds ? KINDS[name] : (t ?? UNKNOWN);
	let kept = filter(alternatives(t), (m) => {
		let o = ofKind(m, name);
		return o === null || o === holds;
	});
	if (!length(kept)) return holds ? KINDS[name] : t;
	return unionOf(kept);
}

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
//   { kind: 'kind', name, positive, typeName }
//       type(x) === 'object' / 'array' / 'function' (or !==): x keeps, or
//       loses, the types of that shape (narrowKind).
//
//   { kind: 'variant', name, field, value, positive }
//       Discriminant test r.field === <literal> (positive=true) or !==. Refines
//       a tagged union bound to `name` to the matching variant(s) per branch.
//
//   A guard's name may be a member path, `a.b.c`, with `root` its variable
//   (a): applyGuard then narrows the path (scope.paths), whose type the
//   inferrer narrows in turn (applyPathNarrowing).
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

// The root variable of an access chain holding a `?.` link (`x?.a`,
// `x.a?.[i]`), or null. Such a chain is non-null only if x is: a `?.` on null
// short-circuits to null, a plain access on null throws.
export function optionalChainRoot(node, source) {
	let opt = false;
	while (node) {
		let t = ts.nodeType(node);
		if (t !== 'member_expression' && t !== 'subscript_expression') break;
		if (ts.childByField(node, 'optional_chain')) opt = true;
		node = ts.childByField(node, 'object');
	}
	return (opt && node && ts.nodeType(node) === 'identifier') ? ts.text(node, source) : null;
};

// `a.b.c` as { path: 'a.b.c', root: 'a' }, `?.` links too (where the chain is
// not null they read the same); null for anything else.
export function pathOf(node, source) {
	let props = [];
	while (node && ts.nodeType(node) === 'member_expression') {
		let prop = ts.childByField(node, 'property');
		if (!prop || ts.nodeType(prop) !== 'property_identifier') return null;
		unshift(props, ts.text(prop, source));
		node = ts.childByField(node, 'object');
	}
	if (!node || ts.nodeType(node) !== 'identifier') return null;
	let root = ts.text(node, source);
	return { path: join('.', [ root, ...props ]), root };
};

// What a guard on node narrows: a variable { name } or a member path
// { name, root }; null for anything else.
function guardTarget(node, source) {
	if (!node) return null;
	if (ts.nodeType(node) === 'identifier') return { name: ts.text(node, source) };
	let p = pathOf(node, source);
	return p ? { name: p.path, root: p.root } : null;
}

// The objects along a chain holding a `?.` link that are variables or member
// paths: each was read without short-circuiting or throwing where the chain is
// not null. [] for any other node.
function chainObjects(node, source) {
	let objs = [], opt = false;
	while (node) {
		let t = ts.nodeType(node);
		if (t !== 'member_expression' && t !== 'subscript_expression') break;
		if (ts.childByField(node, 'optional_chain')) opt = true;
		node = ts.childByField(node, 'object');
		let g = guardTarget(node, source);
		if (g) push(objs, g);
	}
	return opt ? objs : [];
}

// The targets are non-null in the branch where the condition is `holds`.
function nonNullWhen(targets, holds) {
	let guards = map(targets, (t) => ({ kind: 'truthy', ...t, positive: holds }));
	return holds ? { kind: 'and', guards } : { kind: 'or', guards };
}

// A truthy test of node (`if (x)`, `!x` when not `holds`): x, or for a chain
// with a `?.` link, it and the objects along it.
function truthyGuard(node, holds, source) {
	let target = guardTarget(node, source);
	let objs = chainObjects(node, source);
	if (!length(objs))
		return target ? { kind: 'truthy', ...target, positive: holds } : null;
	if (target) push(objs, target);
	return nonNullWhen(objs, holds);
}

export function parseGuard(node, source) {
	if (!node) return null;
	let nt = ts.nodeType(node);

	if (nt === 'parenthesized_expression')
		return parseGuard(firstNamed(node), source);

	// `if (x)`, `if (a.b)`, `if (x?.p)`
	let truthy = truthyGuard(node, true, source);
	if (truthy) return truthy;

	if (nt === 'unary_expression') {
		if (ts.nodeType(ts.childByField(node, 'operator')) === '!') {
			let operand = ts.childByField(node, 'argument');
			return operand ? truthyGuard(operand, false, source) : null;
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
				// type(x?.p) == 'T' for a non-null T: x and x.p are non-null
				// where it holds.
				let objs = operand ? chainObjects(operand, source) : [];
				let target = guardTarget(operand, source);
				let typeName = replace(ts.text(stringSide, source), /^['"]|['"]$/g, '');
				if (length(objs) && typeName !== 'null') {
					if (target) push(objs, target);
					return nonNullWhen(objs, isEq);
				}
				if (target) {
					let toType = TYPE_FUNC_MAP[typeName];
					if (toType)
						return { kind: 'type', ...target, positive: isEq, toType };
					if (KINDS[typeName])
						return { kind: 'kind', ...target, positive: isEq, typeName };
					// object/array/function have no singleton type, but
					// `type(x) === '<non-null kind>'` still proves x is non-null
					// where it holds (type(null) is 'null'), and `!==` where it
					// fails: only that branch narrows, x could be null in the other.
					return nonNullWhen([ target ], isEq);
				}
			}
		}

		// x?.p == <literal> (or != null): x and x.p are non-null where the
		// chain is.
		for (let pair in [[left, right], [right, left]]) {
			let objs = chainObjects(pair[0], source);
			if (!length(objs)) continue;
			let target = guardTarget(pair[0], source);
			if (target) push(objs, target);
			if (ts.nodeType(pair[1]) === 'null') return nonNullWhen(objs, isNotEq);
			if (literalNodeValue(pair[1], source) !== null) return nonNullWhen(objs, isEq);
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

		// x !== null  /  x === null  (or a.b)
		let target = null;
		if (ts.nodeType(right) === 'null')
			target = guardTarget(left, source);
		else if (ts.nodeType(left) === 'null')
			target = guardTarget(right, source);
		if (!target) return null;

		return { kind: 'truthy', ...target, positive: isNotEq };
	}

	return null;
};

// Narrow scope, a fresh one for the branch, by guard: its variables' bindings,
// and its member paths in scope.paths (see scope.uc pathNarrowing).
export function applyGuard(scope, guard, positive) {
	if (!guard) return;
	scope.narrow = true;
	if (guard.kind === 'and' || guard.kind === 'or') {
		// `and` holds every sub-guard when true, `or` fails every one when
		// false; the other branch is ambiguous.
		if (positive === (guard.kind === 'and'))
			for (let i = 0; i < length(guard.guards); i++)
				applyGuard(scope, guard.guards[i], positive);
		return;
	}
	let inTrueBranch = guard.positive ? positive : !positive;
	if (guard.root) {
		if (guard.kind !== 'truthy' && guard.kind !== 'type' && guard.kind !== 'kind') return;
		let n = { kind: guard.kind, holds: inTrueBranch };
		if (guard.kind === 'type') n.toType = guard.toType;
		if (guard.kind === 'kind') n.typeName = guard.typeName;
		scope.paths ??= {};
		scope.paths[guard.name] = n;
		return;
	}
	let current = scopeGet(scope, guard.name);
	if (guard.kind === 'variant') {
		scopeSet(scope, guard.name,
			narrowUnionByDiscriminant(current ?? UNKNOWN, guard.field, guard.value, inTrueBranch));
	} else if (guard.kind === 'type') {
		scopeSet(scope, guard.name, inTrueBranch
			? guard.toType
			: narrowExcluding(current ?? UNKNOWN, guard.toType));
	} else if (guard.kind === 'kind') {
		scopeSet(scope, guard.name, narrowKind(current ?? UNKNOWN, guard.typeName, inTrueBranch));
	} else {
		// kind === 'truthy'
		scopeSet(scope, guard.name, inTrueBranch ? narrowToNonNull(current ?? UNKNOWN) : NULL_T);
	}
};

// The type of a member whose path a guard narrowed (applyGuard's n).
export function applyPathNarrowing(type, n) {
	if (n.kind === 'type') return n.holds ? n.toType : narrowExcluding(type ?? UNKNOWN, n.toType);
	if (n.kind === 'kind') return narrowKind(type, n.typeName, n.holds);
	return n.holds ? narrowToNonNull(type) : NULL_T;
};
