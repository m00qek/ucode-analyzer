import * as type_registry from 'code_analysis.types.registry';
import { substitute } from 'code_analysis.types.unifier';

export let UNKNOWN = { kind: 'unknown' };
export let BOOL    = { kind: 'primitive', name: 'boolean' };
export let STR     = { kind: 'primitive', name: 'string' };
export let INT     = { kind: 'primitive', name: 'int' };
export let FLOAT   = { kind: 'primitive', name: 'float' };
export let NULL_T  = { kind: 'primitive', name: 'null' };

// Reduce a list of Types to a single type: UNKNOWN for empty, the sole element
// for a singleton, or a union of distinct types otherwise.
export function unionOf(types) {
	let members = [];
	for (let i = 0; i < length(types); i++) {
		let t = types[i];
		let seen = false;
		for (let j = 0; j < length(members); j++) {
			let m = members[j];
			if (m.kind !== t.kind) continue;
			if (t.kind === 'primitive' && m.name !== t.name) continue;
			if (t.kind === 'ref'       && m.name !== t.name) continue;
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
