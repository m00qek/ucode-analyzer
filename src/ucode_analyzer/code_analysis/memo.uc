let _cache = {};       // uri → { 'startByte|nodeType|scopeId' → Type }
let _docMaps = {};     // uri → { parentKey → { childStartByte → docText|null } }

// Each text of a uri is an epoch, whose caches are the two above. A function
// type inferred from an older text, which a scope map reused across an edit
// still holds, infers its return type in its own epoch (enterEpoch): its nodes
// are the older tree's, whose byte ranges mean other nodes now.
let _epochs = {};      // uri → { now, active, buckets: { epoch → { types, docs } } }

function slot(uri) {
	if (!_epochs[uri]) {
		let b = { types: _cache[uri] ?? {}, docs: _docMaps[uri] ?? {} };
		_epochs[uri] = { now: 0, active: 0, buckets: { '0': b } };
		_cache[uri] = b.types;
		_docMaps[uri] = b.docs;
	}
	return _epochs[uri];
}

// The epoch whose caches are in use for uri: an older one while a function
// type inferred from an older text infers its return type.
export function epochOf(uri) {
	return slot(uri).active;
};

// Where the offsets of a text moved in the next one, for each text a scope map
// reused parts of: uri → { epoch → { next, start, oldEnd, delta } }.
let _moves = {};

// The text of epoch `from` became uri's current one through edit
// { start, oldEnd, delta }.
export function recordMove(uri, from, edit) {
	let now = slot(uri).now;
	if (from !== now)
		(_moves[uri] ??= {})[from] = { next: now, start: edit.start, oldEnd: edit.oldEnd, delta: edit.delta };
};

export function forgetMoves(uri) {
	delete _moves[uri];
};

// An offset into uri's text of the epoch in use, which anchorOffset finds in a
// later text.
export function anchor(uri, offset) {
	return { kind: 'anchor', uri, epoch: slot(uri).active, offset };
};

// Where anchor a is in its uri's current text; null when an edit since changed
// what was there, or the texts in between are not known.
export function anchorOffset(a) {
	let now = slot(a.uri).now, e = a.epoch, offset = a.offset;
	while (e !== now) {
		let m = _moves[a.uri]?.[e];
		if (!m || (offset >= m.start && offset < m.oldEnd)) return null;
		if (offset >= m.oldEnd) offset += m.delta;
		e = m.next;
	}
	return offset;
};

// Make epoch e's caches the ones in use for uri; returns the epoch it replaces.
export function enterEpoch(uri, e) {
	let s = slot(uri);
	let prev = s.active;
	if (e !== prev) {
		let b = s.buckets[e] ??= { types: {}, docs: {} };
		_cache[uri] = b.types;
		_docMaps[uri] = b.docs;
		s.active = e;
	}
	return prev;
};

// The inference recursion caps at a fixed depth; a node first computed near the
// cap may have a truncated (unknown) subtree. Each entry records the depth it was
// computed at (smaller depth = more remaining budget). A cached value is only
// reused for a query with equal-or-less budget (equal-or-greater depth), and
// memoSet keeps whichever entry was computed with the most budget — so a deep,
// possibly-truncated result can't poison a later shallow query. `depth` is
// optional: get defaults to max budget and set to 0, keeping the plain cache
// semantics for non-inference callers.
export function memoGet(uri, offset, nodeType, scopeId, depth) {
	let bucket = _cache[uri];
	let key = offset + '|' + nodeType + '|' + scopeId;
	let e = (bucket && exists(bucket, key)) ? bucket[key] : null;
	if (!e) return null;
	return (e.depth <= (depth ?? 999)) ? e.type : null;
};

export function memoSet(uri, offset, nodeType, scopeId, type, depth) {
	if (!_cache[uri]) slot(uri);
	let key = offset + '|' + nodeType + '|' + scopeId;
	let d = depth ?? 0;
	let existing = _cache[uri][key];
	if (!existing || d < existing.depth)
		_cache[uri][key] = { depth: d, type };
};

// Per-parent docBeforeMap cache. precedingDoc resolves the /** */ before a
// function/declaration by scanning its parent's children; caching the whole
// parent's map turns a file-wide inference pass from O(functions²) into O(n).
// The key must be content-sensitive (like the type memo's byte-offset keys):
// the parent's start byte alone is 0 for every top-level program, so callers
// pass 'startByte|endByte' so a re-opened document under the same uri (tests
// do not invalidate between opens) doesn't read a stale sibling's map.
export function docMapGet(uri, parentKey) {
	let bucket = _docMaps[uri];
	return (bucket && exists(bucket, parentKey)) ? bucket[parentKey] : null;
};

export function docMapSet(uri, parentKey, map) {
	if (!_docMaps[uri]) slot(uri);
	_docMaps[uri][parentKey] = map;
};

// A new text for uri: a new epoch, the older ones' caches dropped.
export function invalidateUri(uri) {
	let now = (_epochs[uri]?.now ?? 0) + 1;
	let b = { types: {}, docs: {} };
	_epochs[uri] = { now, active: now, buckets: { [now]: b } };
	_cache[uri] = b.types;
	_docMaps[uri] = b.docs;
};
