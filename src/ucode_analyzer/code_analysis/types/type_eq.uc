import { returnOf } from 'ucode_analyzer.code_analysis.types.unifier';

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
