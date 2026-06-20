export function makeScope(parent) {
	return { bindings: {}, parent: parent ?? null };
};

export function scopeSet(scope, name, type) {
	scope.bindings[name] = type;
};

export function scopeGet(scope, name) {
	if (scope.bindings[name] !== null) return scope.bindings[name];
	if (scope.parent) return scopeGet(scope.parent, name);
	return null;
};
