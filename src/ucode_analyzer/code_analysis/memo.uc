import { buildLineTable } from 'ucode_analyzer.code_analysis.positions';

let _cache = {};       // uri → { 'startByte|nodeType|scopeId' → Type }
let _docMaps = {};     // uri → { parentKey → { childStartByte → docText|null } }
let _lineTables = {};  // uri → { src, table }

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
	if (!_cache[uri]) _cache[uri] = {};
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
	if (!_docMaps[uri]) _docMaps[uri] = {};
	_docMaps[uri][parentKey] = map;
};

// Line table for a source, cached per uri. Inference builds many objects from
// one file text; each would otherwise rebuild the whole-file line table. Keyed
// by string identity (source === cached.src is a fast native compare, no
// staleness possible) rather than a length/offset proxy, so it's correct even
// on the test path where a uri is re-opened without invalidation.
export function lineTableFor(uri, source) {
	let cached = _lineTables[uri];
	if (cached && cached.src === source) return cached.table;
	let table = buildLineTable(source);
	_lineTables[uri] = { src: source, table };
	return table;
};

export function invalidateUri(uri) {
	delete _cache[uri];
	delete _docMaps[uri];
	delete _lineTables[uri];
};
