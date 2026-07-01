let _cache = {};  // uri → { 'startByte|nodeType|scopeId' → Type }

export function memoGet(uri, offset, nodeType, scopeId) {
	let bucket = _cache[uri];
	let key = offset + '|' + nodeType + '|' + scopeId;
	return (bucket && exists(bucket, key)) ? bucket[key] : null;
};

export function memoSet(uri, offset, nodeType, scopeId, type) {
	if (!_cache[uri]) _cache[uri] = {};
	_cache[uri][offset + '|' + nodeType + '|' + scopeId] = type;
};

export function invalidateUri(uri) {
	delete _cache[uri];
};
