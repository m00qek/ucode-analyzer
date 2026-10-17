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

// A loop, not recursion: chains run 40 to 80 scopes deep in large files.
export function scopeGet(scope, name) {
	for (let s = scope; s; s = s.parent)
		if (exists(s.bindings, name)) return s.bindings[name];
	return null;
};

// True when `name` resolves to the root scope — the builtins — rather than a
// local, import or parameter that shadows it.
export function isRootBinding(scope, name) {
	for (let s = scope; s; s = s.parent)
		if (exists(s.bindings, name)) return s.parent === null;
	return false;
};

export function scopeHas(scope, name) {
	let s = scope;
	while (s) {
		if (exists(s.bindings, name)) return true;
		s = s.parent;
	}
	return false;
};
