let _cache = {};    // uri → { 'startByte|nodeType|scopeId' → Type }
let _docMaps = {};  // uri → { parentStartByte → { childStartByte → docText|null } }

export function memoGet(uri, offset, nodeType, scopeId) {
	let bucket = _cache[uri];
	let key = offset + '|' + nodeType + '|' + scopeId;
	return (bucket && exists(bucket, key)) ? bucket[key] : null;
};

export function memoSet(uri, offset, nodeType, scopeId, type) {
	if (!_cache[uri]) _cache[uri] = {};
	_cache[uri][offset + '|' + nodeType + '|' + scopeId] = type;
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
	if (!_docMaps[uri]) _docMaps[uri] = {};
	_docMaps[uri][parentKey] = map;
};

export function invalidateUri(uri) {
	delete _cache[uri];
	delete _docMaps[uri];
};
