export function makeScope(parent) {
	return { bindings: {}, parent: parent ?? null };
};

export function scopeSet(scope, name, type) {
	scope.bindings[name] = type;
};

export function scopeGet(scope, name) {
	if (exists(scope.bindings, name)) return scope.bindings[name];
	if (scope.parent) return scopeGet(scope.parent, name);
	return null;
};

export function scopeHas(scope, name) {
	let s = scope;
	while (s) {
		if (exists(s.bindings, name)) return true;
		s = s.parent;
	}
	return false;
};
