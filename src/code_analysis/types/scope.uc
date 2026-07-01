let _nextId = 0;

export function makeScope(parent) {
	return { id: _nextId++, bindings: {}, parent: parent ?? null };
};

export function scopeSet(scope, name, type) {
	scope.bindings[name] = type;
};

// COW declaration: returns a new scope overlay with one binding added.
// Use this instead of scopeSet when the current scope may already be
// captured in a checkpoint (i.e. during the unified top-down walk).
export function scopeFork(scope, name, type) {
	let s = makeScope(scope);
	s.bindings[name] = type;
	return s;
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
