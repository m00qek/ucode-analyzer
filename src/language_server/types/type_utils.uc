import * as type_registry from 'language_server.types.registry';

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

// Look up a member name in a resolved type. Expands ref types via the registry.
export function memberOfType(type, propName) {
	if (!type) return UNKNOWN;
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
	if (type.kind === 'ref') {
		let def = type_registry.lookup(type.name);
		if (def) return memberOfType(def.type, propName);
	}
	return UNKNOWN;
};
