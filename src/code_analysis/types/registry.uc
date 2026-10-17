let _registry = {};  // name → { type, sourceUri, params }

// params is the ordered list of @template parameter names declared alongside the
// typedef (e.g. ['T'] for `@template T` on a `@typedef ... Foo`); it lets ref
// resolution substitute the ref's type arguments. Defaults to none.
export function register(name, type, sourceUri, params) {
	_registry[name] = { type, sourceUri, params: params ?? [] };
};

export function lookup(name) {
	return _registry[name] ?? null;
};

export function removeUri(uri) {
	for (let name in keys(_registry))
		if (_registry[name].sourceUri === uri)
			delete _registry[name];
};

// The typedefs that uri declares, by name.
export function definedIn(uri) {
	let out = {};
	for (let name, entry in _registry)
		if (entry.sourceUri === uri)
			out[name] = { type: entry.type, params: entry.params };
	return out;
};

export function allNames() {
	return keys(_registry);
};
