let _cache = {};  // uri → { offset → Type }

export function memoGet(uri, offset) {
	let bucket = _cache[uri];
	return (bucket && bucket[offset] !== null) ? bucket[offset] : null;
};

export function memoSet(uri, offset, type) {
	if (!_cache[uri]) _cache[uri] = {};
	_cache[uri][offset] = type;
};

export function invalidateUri(uri) {
	delete _cache[uri];
};
