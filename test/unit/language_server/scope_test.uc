import { describe, it, assert } from 'utest';
import { makeScope, scopeGet, scopeSet } from 'ucode_language_server.types.scope';

let INT = { kind: 'primitive', name: 'int' };
let STR = { kind: 'primitive', name: 'string' };

describe('scope', () => {
	it('scopeGet returns null for unknown name', () => {
		let s = makeScope(null);
		assert.match(null, scopeGet(s, 'x'));
	});

	it('scopeSet and scopeGet work in same scope', () => {
		let s = makeScope(null);
		scopeSet(s, 'x', INT);
		assert.match(INT, scopeGet(s, 'x'));
	});

	it('scopeGet traverses parent chain', () => {
		let parent = makeScope(null);
		scopeSet(parent, 'x', STR);
		let child = makeScope(parent);
		assert.match(STR, scopeGet(child, 'x'));
	});

	it('child binding shadows parent', () => {
		let parent = makeScope(null);
		scopeSet(parent, 'x', STR);
		let child = makeScope(parent);
		scopeSet(child, 'x', INT);
		assert.match(INT, scopeGet(child, 'x'));
		assert.match(STR, scopeGet(parent, 'x'));
	});

	it('child mutations do not affect parent', () => {
		let parent = makeScope(null);
		let child = makeScope(parent);
		scopeSet(child, 'y', INT);
		assert.match(null, scopeGet(parent, 'y'));
	});

	it('three-level chain resolves to grandparent', () => {
		let grandparent = makeScope(null);
		scopeSet(grandparent, 'g', STR);
		let parent = makeScope(grandparent);
		let child  = makeScope(parent);
		assert.match(STR, scopeGet(child, 'g'));
	});
});
