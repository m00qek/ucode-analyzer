// Match paramType against argType, populating bindings in place.
// depth guards against recursive generic types — bail silently above 5.
export function unify(paramType, argType, bindings, depth) {
	if (!paramType || !argType || depth > 5) return;
	let pk = paramType.kind;

	if (pk === 'param') {
		if (!bindings[paramType.name])
			bindings[paramType.name] = argType;
		return;
	}

	if (pk === 'generic' && argType.kind === 'generic' && paramType.base === argType.base) {
		let n = min(length(paramType.params), length(argType.params));
		for (let i = 0; i < n; i++)
			unify(paramType.params[i], argType.params[i], bindings, depth + 1);
		return;
	}

	if (pk === 'ref' && argType.kind === 'ref' && paramType.name === argType.name) {
		let n = min(length(paramType.params), length(argType.params));
		for (let i = 0; i < n; i++)
			unify(paramType.params[i], argType.params[i], bindings, depth + 1);
		return;
	}

	if (pk === 'nullable' && argType.kind === 'nullable') {
		unify(paramType.inner, argType.inner, bindings, depth + 1);
		return;
	}

	if (pk === 'function' && argType.kind === 'function') {
		let n = min(length(paramType.params), length(argType.params));
		for (let i = 0; i < n; i++)
			unify(paramType.params[i].type, argType.params[i].type, bindings, depth + 1);
		unify(paramType.return, argType.return, bindings, depth + 1);
		return;
	}

	if (pk === 'union' && argType.kind === 'union') {
		let n = min(length(paramType.members), length(argType.members));
		for (let i = 0; i < n; i++)
			unify(paramType.members[i], argType.members[i], bindings, depth + 1);
	}
};

// Apply bindings to type, replacing every {kind:'param'} node with its bound type.
export function substitute(type, bindings) {
	if (!type) return type;
	let k = type.kind;

	if (k === 'param')
		return bindings[type.name] ?? type;

	if (k === 'generic') {
		let params = map(type.params, (p) => substitute(p, bindings));
		return { kind: 'generic', base: type.base, params };
	}

	if (k === 'ref' && length(type.params)) {
		let params = map(type.params, (p) => substitute(p, bindings));
		return { kind: 'ref', name: type.name, params };
	}

	if (k === 'nullable')
		return { kind: 'nullable', inner: substitute(type.inner, bindings) };

	if (k === 'union') {
		let members = map(type.members, (m) => substitute(m, bindings));
		return { kind: 'union', members };
	}

	if (k === 'record') {
		let fields = map(type.fields, (f) => ({ name: f.name, type: substitute(f.type, bindings) }));
		return { kind: 'record', fields };
	}

	if (k === 'function') {
		let params = map(type.params, (p) => ({ name: p.name, type: substitute(p.type, bindings) }));
		return { kind: 'function', params, return: substitute(type.return, bindings) };
	}

	return type;
};
