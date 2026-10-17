import { describe, it, assert, beforeEach } from 'utest';
import { memoGet, memoSet, invalidateUri } from 'ucode_analyzer.code_analysis.memo';

let URI_A = 'file:///a.uc';
let URI_B = 'file:///b.uc';
let INT   = { kind: 'primitive', name: 'int' };
let STR   = { kind: 'primitive', name: 'string' };

beforeEach(() => {
	invalidateUri(URI_A);
	invalidateUri(URI_B);
});

describe('memo', () => {
	it('returns null on miss', () => {
		assert.match(null, memoGet(URI_A, 0, 'identifier', 1));
	});

	it('returns cached value on hit', () => {
		memoSet(URI_A, 10, 'identifier', 1, INT);
		assert.match(INT, memoGet(URI_A, 10, 'identifier', 1));
	});

	it('different offsets are independent', () => {
		memoSet(URI_A, 10, 'identifier', 1, INT);
		memoSet(URI_A, 20, 'identifier', 1, STR);
		assert.match(INT, memoGet(URI_A, 10, 'identifier', 1));
		assert.match(STR, memoGet(URI_A, 20, 'identifier', 1));
	});

	it('same offset different nodeTypes are independent', () => {
		memoSet(URI_A, 5, 'identifier', 1, INT);
		memoSet(URI_A, 5, 'call_expression', 1, STR);
		assert.match(INT, memoGet(URI_A, 5, 'identifier', 1));
		assert.match(STR, memoGet(URI_A, 5, 'call_expression', 1));
	});

	it('different URIs are independent', () => {
		memoSet(URI_A, 5, 'identifier', 1, INT);
		memoSet(URI_B, 5, 'identifier', 1, STR);
		assert.match(INT, memoGet(URI_A, 5, 'identifier', 1));
		assert.match(STR, memoGet(URI_B, 5, 'identifier', 1));
	});

	it('invalidateUri clears all offsets for that URI', () => {
		memoSet(URI_A, 10, 'identifier', 1, INT);
		memoSet(URI_A, 20, 'identifier', 1, STR);
		invalidateUri(URI_A);
		assert.match(null, memoGet(URI_A, 10, 'identifier', 1));
		assert.match(null, memoGet(URI_A, 20, 'identifier', 1));
	});

	it('invalidateUri does not affect other URIs', () => {
		memoSet(URI_A, 5, 'identifier', 1, INT);
		memoSet(URI_B, 5, 'identifier', 1, STR);
		invalidateUri(URI_A);
		assert.match(STR, memoGet(URI_B, 5, 'identifier', 1));
	});

	it('same offset same nodeType different scopeId: independent cache entries', () => {
		memoSet(URI_A, 5, 'identifier', 10, INT);
		memoSet(URI_A, 5, 'identifier', 20, STR);
		assert.match(INT, memoGet(URI_A, 5, 'identifier', 10));
		assert.match(STR, memoGet(URI_A, 5, 'identifier', 20));
	});

	it('same offset same nodeType unknown scopeId: cache miss', () => {
		memoSet(URI_A, 5, 'identifier', 10, INT);
		assert.match(null, memoGet(URI_A, 5, 'identifier', 99));
	});

	// depth budget: an entry computed at depth d may be truncated; it may only be
	// reused for a query with equal-or-less budget (equal-or-greater depth).
	it('reuses a shallow-computed value for a deeper (less-budget) query', () => {
		memoSet(URI_A, 10, 'identifier', 1, INT, 3);       // computed at depth 3
		assert.match(INT, memoGet(URI_A, 10, 'identifier', 1, 3));   // equal depth
		assert.match(INT, memoGet(URI_A, 10, 'identifier', 1, 6));   // deeper = less budget
	});

	it('does not reuse a deep (possibly truncated) value for a shallower query', () => {
		memoSet(URI_A, 10, 'identifier', 1, INT, 8);       // computed deep
		assert.match(null, memoGet(URI_A, 10, 'identifier', 1, 2));  // shallow query recomputes
	});

	it('keeps the shallowest-computed entry, ignoring a later deeper write', () => {
		memoSet(URI_A, 10, 'identifier', 1, STR, 8);
		memoSet(URI_A, 10, 'identifier', 1, INT, 2);       // shallower wins
		memoSet(URI_A, 10, 'identifier', 1, STR, 5);       // deeper: ignored
		assert.match(INT, memoGet(URI_A, 10, 'identifier', 1, 8));
	});
});
