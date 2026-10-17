import * as type_registry from 'ucode_analyzer.code_analysis.types.registry';
import { substitute } from 'ucode_analyzer.code_analysis.types.unifier';

export let UNKNOWN = { kind: 'unknown' };
export let BOOL    = { kind: 'primitive', name: 'boolean' };
export let STR     = { kind: 'primitive', name: 'string' };
export let INT     = { kind: 'primitive', name: 'int' };
export let FLOAT   = { kind: 'primitive', name: 'float' };
export let NULL_T  = { kind: 'primitive', name: 'null' };

// A literal type is a primitive refined with a concrete `value` (e.g. the string
// 'fail'). It is deliberately NOT a distinct kind: every `kind === 'primitive'` /
// `name === 'string'` check keeps working unchanged, and literal-awareness is
// opt-in only where it matters (union dedup, discriminant narrowing). Literals
// widen back to their base type anywhere the value is not needed.
export function literal(name, value) {
	return { kind: 'primitive', name, value };
};

export function widen(type) {
	if (type && type.kind === 'primitive' && exists(type, 'value'))
		return { kind: 'primitive', name: type.name };
	return type;
};

// Two records are the "same" for union-dedup purposes when they carry the same
// set of field names — enough to keep tagged variants ({kind:'fail', value,
// error} vs {kind:'pass'}) distinct while still collapsing repeated shapes.
function sameFieldNames(a, b) {
	let af = a.fields ?? [];
	let bf = b.fields ?? [];
	if (length(af) !== length(bf)) return false;
	let an = sort(map(af, (f) => f.name));
	let bn = sort(map(bf, (f) => f.name));
	for (let i = 0; i < length(an); i++)
		if (an[i] !== bn[i]) return false;
	return true;
}

// Two records of the same field names as one: each field's type is the union
// of both (`{ a: 1 }` and `{ a: 2 }` give `{ a: 1 | 2 }`). `union` is unionOf.
function mergeRecords(a, b, union) {
	let bt = {};
	for (let f in (b.fields ?? [])) bt[f.name] = f.type;
	let r = { ...a, fields: map(a.fields ?? [], (f) =>
		(f.type && bt[f.name]) ? { ...f, type: union([f.type, bt[f.name]]) } : f) };
	if (b.open) r.open = true;
	return r;
}

// Reduce a list of Types to a single type: UNKNOWN for empty, the sole element
// for a singleton, or a union of distinct types otherwise.
// Nested unions are flattened: `(a | b) | c` is `a | b | c`, so a member
// such as null is never hidden one level down.
export function unionOf(types) {
	let flat = [];
	for (let t in types) {
		if (t && t.kind === 'union') push(flat, ...t.members); else push(flat, t);
	}
	types = flat;
	let members = [];
	for (let i = 0; i < length(types); i++) {
		let t = types[i];
		let seen = false;
		for (let j = 0; j < length(members); j++) {
			let m = members[j];
			if (m.kind !== t.kind) continue;
			if (t.kind === 'primitive') {
				if (m.name !== t.name) continue;
				let mv = exists(m, 'value'), tv = exists(t, 'value');
				// Different literal values stay distinct ('a' | 'b'); a literal
				// alongside its own bare base widens to the base.
				if (mv && tv && m.value !== t.value) continue;
				if (mv && !tv) members[j] = t;
				seen = true; break;
			}
			if (t.kind === 'ref' && m.name !== t.name) continue;
			// Distinct record shapes are kept apart so tagged unions survive.
			if (t.kind === 'record') {
				if (!sameFieldNames(m, t)) continue;
				members[j] = mergeRecords(m, t, unionOf);
			}
			seen = true; break;
		}
		if (!seen) push(members, t);
	}
	if (length(members) === 0) return UNKNOWN;
	if (length(members) === 1) return members[0];
	return { kind: 'union', members };
};

// Expand a ref type to its underlying @typedef target, substituting the ref's
// type arguments for the typedef's @template params. Chains of refs are followed
// with a cycle/depth guard; non-ref types and unresolved/cyclic refs are returned
// unchanged, so callers can treat "still a ref" as "give up / assume OK".
export function resolveRef(type) {
	let seen  = {};
	let depth = 0;
	while (type && type.kind === 'ref') {
		if (++depth > 32 || seen[type.name]) break;
		seen[type.name] = true;
		let def = type_registry.lookup(type.name);
		if (!def) break;
		let target  = def.type;
		let tparams = def.params ?? [];
		if (length(type.params) && length(tparams)) {
			let bindings = {};
			let n = min(length(tparams), length(type.params));
			for (let i = 0; i < n; i++)
				bindings[tparams[i]] = type.params[i];
			target = substitute(target, bindings);
		}
		type = target;
	}
	return type ?? UNKNOWN;
};

// Look up a member name in a resolved type. Expands ref types via the registry.
export function memberOfType(type, propName) {
	if (!type) return UNKNOWN;
	type = resolveRef(type);
	if (type.kind === 'nullable')
		return memberOfType(type.inner, propName);
	if (type.kind === 'union') {
		let results = [];
		for (let i = 0; i < length(type.members); i++) {
			let t = memberOfType(type.members[i], propName);
			if (t.kind !== 'unknown') push(results, t);
		}
		return unionOf(results);
	}
	if (type.kind === 'record') {
		for (let i = 0; i < length(type.fields); i++)
			if (type.fields[i].name === propName) return type.fields[i].type;
		return UNKNOWN;
	}
	return UNKNOWN;
};
