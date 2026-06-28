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
		assert.match(null, memoGet(URI_A, 0, 'identifier'));
	});

	it('returns cached value on hit', () => {
		memoSet(URI_A, 10, 'identifier', INT);
		assert.match(INT, memoGet(URI_A, 10, 'identifier'));
	});

	it('different offsets are independent', () => {
		memoSet(URI_A, 10, 'identifier', INT);
		memoSet(URI_A, 20, 'identifier', STR);
		assert.match(INT, memoGet(URI_A, 10, 'identifier'));
		assert.match(STR, memoGet(URI_A, 20, 'identifier'));
	});

	it('same offset different nodeTypes are independent', () => {
		memoSet(URI_A, 5, 'identifier', INT);
		memoSet(URI_A, 5, 'call_expression', STR);
		assert.match(INT, memoGet(URI_A, 5, 'identifier'));
		assert.match(STR, memoGet(URI_A, 5, 'call_expression'));
	});

	it('different URIs are independent', () => {
		memoSet(URI_A, 5, 'identifier', INT);
		memoSet(URI_B, 5, 'identifier', STR);
		assert.match(INT, memoGet(URI_A, 5, 'identifier'));
		assert.match(STR, memoGet(URI_B, 5, 'identifier'));
	});

	it('invalidateUri clears all offsets for that URI', () => {
		memoSet(URI_A, 10, 'identifier', INT);
		memoSet(URI_A, 20, 'identifier', STR);
		invalidateUri(URI_A);
		assert.match(null, memoGet(URI_A, 10, 'identifier'));
		assert.match(null, memoGet(URI_A, 20, 'identifier'));
	});

	it('invalidateUri does not affect other URIs', () => {
		memoSet(URI_A, 5, 'identifier', INT);
		memoSet(URI_B, 5, 'identifier', STR);
		invalidateUri(URI_A);
		assert.match(STR, memoGet(URI_B, 5, 'identifier'));
	});
});
