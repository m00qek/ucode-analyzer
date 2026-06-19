import { describe, it, assert, beforeEach } from 'utest';
import { memoGet, memoSet, invalidateUri } from 'ucode_language_server.memo';

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
		assert.match(null, memoGet(URI_A, 0));
	});

	it('returns cached value on hit', () => {
		memoSet(URI_A, 10, INT);
		assert.match(INT, memoGet(URI_A, 10));
	});

	it('different offsets are independent', () => {
		memoSet(URI_A, 10, INT);
		memoSet(URI_A, 20, STR);
		assert.match(INT, memoGet(URI_A, 10));
		assert.match(STR, memoGet(URI_A, 20));
	});

	it('different URIs are independent', () => {
		memoSet(URI_A, 5, INT);
		memoSet(URI_B, 5, STR);
		assert.match(INT, memoGet(URI_A, 5));
		assert.match(STR, memoGet(URI_B, 5));
	});

	it('invalidateUri clears all offsets for that URI', () => {
		memoSet(URI_A, 10, INT);
		memoSet(URI_A, 20, STR);
		invalidateUri(URI_A);
		assert.match(null, memoGet(URI_A, 10));
		assert.match(null, memoGet(URI_A, 20));
	});

	it('invalidateUri does not affect other URIs', () => {
		memoSet(URI_A, 5, INT);
		memoSet(URI_B, 5, STR);
		invalidateUri(URI_A);
		assert.match(STR, memoGet(URI_B, 5));
	});
});
