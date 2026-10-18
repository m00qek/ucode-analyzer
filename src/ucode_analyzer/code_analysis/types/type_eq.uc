import { returnOf } from 'ucode_analyzer.code_analysis.types.unifier';
import { anchorOffset } from 'ucode_analyzer.code_analysis.memo';

// Past this depth two types count as different.
const MAX_DEPTH = 24;

// True when types a and b are the same, field by field. A function type's
// return type is inferred first on both sides: a lazy one of a reused scope
// map would otherwise be inferred later from the text it was made from.
export function sameType(a, b, depth) {
	if (a === b) return true;
	depth ??= 0;
	if (depth > MAX_DEPTH) return false;
	let ta = type(a);
	if (ta !== type(b)) return false;
	if (ta === 'array') {
		if (length(a) !== length(b)) return false;
		for (let i = 0; i < length(a); i++)
			if (!sameType(a[i], b[i], depth + 1)) return false;
		return true;
	}
	if (ta !== 'object') return a === b;
	// Places in older texts are the same where the edits since moved them.
	if (a.kind === 'anchor' || b.kind === 'anchor') {
		if (a.kind !== b.kind || a.uri !== b.uri) return false;
		let at = anchorOffset(a);
		return at !== null && at === anchorOffset(b);
	}
	if (a.kind === 'function' && b.kind === 'function') {
		returnOf(a);
		returnOf(b);
	}
	let ka = keys(a);
	if (length(ka) !== length(keys(b))) return false;
	for (let k in ka)
		if (!exists(b, k) || !sameType(a[k], b[k], depth + 1)) return false;
	return true;
};

// True when two scopes' own bindings are the same names with the same types.
export function sameBindings(a, b) {
	let ka = keys(a);
	if (length(ka) !== length(keys(b))) return false;
	for (let k in ka)
		if (!exists(b, k) || !sameType(a[k], b[k])) return false;
	return true;
};

// name → type at a scope, past the root (the imports and builtins).
function flatten(scope, memo) {
	if (!scope || !scope.parent) return {};
	if (memo[scope.id]) return memo[scope.id];
	let f = { ...flatten(scope.parent, memo) };
	for (let k, v in scope.bindings) f[k] = v;
	return memo[scope.id] = f;
}

// True when scopes a and b bind the same, level by level up to the root: a
// cheap proof that they see the same names, kept for the checkpoints that
// share levels. Chains that differ in shape can still agree once flattened.
function sameChain(a, b, memo) {
	let path = [], ok;
	for (;;) {
		if (!a?.parent || !b?.parent) { ok = !a?.parent && !b?.parent; break; }
		let k = a.id + ':' + b.id;
		if (exists(memo, k)) { ok = memo[k]; break; }
		push(path, [ k, a, b ]);
		a = a.parent;
		b = b.parent;
	}
	for (let i = length(path) - 1; i >= 0; i--) {
		ok = ok && sameBindings(path[i][1].bindings, path[i][2].bindings);
		memo[path[i][0]] = ok;
	}
	return ok;
}

// Where scope map a differs from b, as a message; null when they agree.
export function mapDifference(a, b) {
	let ma = {}, mb = {}, mc = {};
	if (length(a) !== length(b)) return sprintf('%d checkpoints, %d expected', length(a), length(b));
	for (let i = 0; i < length(a); i++) {
		if (a[i].offset !== b[i].offset) return sprintf('checkpoint %d at %d, %d expected', i, a[i].offset, b[i].offset);
		if (sameChain(a[i].scope, b[i].scope, mc)) continue;
		let fa = flatten(a[i].scope, ma), fb = flatten(b[i].scope, mb);
		if (length(keys(fa)) !== length(keys(fb))) return sprintf('at %d: %J, %J expected', a[i].offset, keys(fa), keys(fb));
		for (let k, v in fb)
			if (!exists(fa, k) || !sameType(fa[k], v)) return sprintf('at %d: %s is %J, %J expected', a[i].offset, k, fa[k], v);
	}
	return null;
};
