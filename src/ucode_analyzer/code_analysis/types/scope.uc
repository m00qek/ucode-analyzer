let _nextId = 0;

// While the scope map records a function's walk (see scope_walk.uc), each
// lookup from inside it that leaves its root scope: { root, reads: { name →
// { found, type, root } } }, the first answer per name.
let _rec = null;

export function recordLookups(rec) {
	let prev = _rec;
	_rec = rec;
	return prev;
};

// Where name resolves from scope: { found, type, root }, root meaning the
// builtins' scope, which has no parent.
export function resolve(scope, name) {
	for (let s = scope; s; s = s.parent)
		if (exists(s.bindings, name)) return { found: true, type: s.bindings[name], root: s.parent === null };
	return { found: false, type: null, root: false };
};

// The lookup of name past the recorded root (from its parent), recorded.
function outer(root, name) {
	let r = _rec.reads[name];
	if (!r) _rec.reads[name] = r = resolve(root.parent, name);
	return r;
}

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
	for (let s = scope; s; s = s.parent) {
		if (exists(s.bindings, name)) return s.bindings[name];
		if (_rec && s === _rec.root) return outer(s, name).type;
	}
	return null;
};

// True when `name` resolves to the root scope — the builtins — rather than a
// local, import or parameter that shadows it.
export function isRootBinding(scope, name) {
	for (let s = scope; s; s = s.parent) {
		if (exists(s.bindings, name)) return s.parent === null;
		if (_rec && s === _rec.root) return outer(s, name).root;
	}
	return false;
};

export function scopeHas(scope, name) {
	let s = scope;
	while (s) {
		if (exists(s.bindings, name)) return true;
		if (_rec && s === _rec.root) return outer(s, name).found;
		s = s.parent;
	}
	return false;
};
