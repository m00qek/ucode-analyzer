let _registry = {};  // name → { type, sourceUri }

export function register(name, type, sourceUri) {
	_registry[name] = { type, sourceUri };
};

export function lookup(name) {
	return _registry[name] ?? null;
};

export function removeUri(uri) {
	for (let name in keys(_registry))
		if (_registry[name].sourceUri === uri)
			delete _registry[name];
};

export function allNames() {
	return keys(_registry);
};
