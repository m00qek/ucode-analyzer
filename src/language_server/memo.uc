let _cache = {};  // uri → { 'startByte|nodeType' → Type }

export function memoGet(uri, offset, nodeType) {
	let bucket = _cache[uri];
	let key = offset + '|' + nodeType;
	return (bucket && exists(bucket, key)) ? bucket[key] : null;
};

export function memoSet(uri, offset, nodeType, type) {
	if (!_cache[uri]) _cache[uri] = {};
	_cache[uri][offset + '|' + nodeType] = type;
};

export function invalidateUri(uri) {
	delete _cache[uri];
};
