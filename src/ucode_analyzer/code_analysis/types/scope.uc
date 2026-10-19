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

// A function's own scope. A member path narrowed outside it (pathNarrowing)
// may have changed by the time it runs.
export function fnScope(parent) {
	let s = makeScope(parent);
	s.fn = true;
	return s;
};

// True when a write to one of kills (paths, or a variable's every member)
// may have changed path.
function killed(kills, path, root) {
	for (let k in kills)
		if (k === root || k === path || substr(path, 0, length(k) + 1) === k + '.') return true;
	return false;
}

// How a guard narrowed member path `path` (`a.b`, root a) where scope is
// (narrowing.uc applyGuard), or null. Until then, nothing may have changed
// it: a write to it or a path it is under (killPaths), a binding of a other
// than a narrowing (`let a`, `a = …`), or a function boundary.
export function pathNarrowing(scope, path, root) {
	for (let s = scope; s; s = s.parent) {
		if (s.paths) {
			if (exists(s.paths, path)) return s.paths[path];
			if (s.kills && killed(s.kills, path, root)) return null;
		}
		if (!s.narrow && exists(s.bindings, root)) return null;
		if (s.fn) return null;
	}
	return null;
};

// A scope past writes to members: kills holds the member paths written
// (`a.b`), and the variables written through a subscript or a delete of one
// (`a`). Narrowings of those paths, and of the paths under them, end there.
export function killPaths(scope, kills) {
	let s = makeScope(scope);
	s.paths = {};
	s.kills = kills;
	return s;
};
