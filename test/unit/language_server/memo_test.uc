import { describe, it, assert, beforeEach } from 'utest';
import { memoGet, memoSet, invalidateUri } from 'language_server.memo';

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
});
