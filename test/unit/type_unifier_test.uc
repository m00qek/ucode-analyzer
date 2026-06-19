import { describe, it, assert } from 'utest';
import { unify, substitute } from 'ucode_language_server.type_unifier';

function prim(name)          { return { kind: 'primitive', name }; }
function param_(name)        { return { kind: 'param', name }; }
function generic(base, elem) { return { kind: 'generic', base, params: [elem] }; }
function list_(elem)         { return generic('list', elem); }
function dict_(val)          { return generic('dict', val); }
function nullable(inner)     { return { kind: 'nullable', inner }; }
function ref(name, params)   { return { kind: 'ref', name, params: params ?? [] }; }
function union_(...ms)       { return { kind: 'union', members: ms }; }
function fn_(params, ret)    { return { kind: 'function', params, return: ret }; }
function np(name, type)      { return { name, type }; }

// Helper: call unify with a fresh bindings object, return it.
function doUnify(paramType, argType) {
	let b = {};
	unify(paramType, argType, b, 0);
	return b;
}

describe('unify', () => {
	it('binds a bare type param to a concrete type', () => {
		let b = doUnify(param_('T'), prim('string'));
		assert.match(prim('string'), b['T']);
	});

	it('recurses into generic list to bind element param', () => {
		let b = doUnify(list_(param_('T')), list_(prim('int')));
		assert.match(prim('int'), b['T']);
	});

	it('recurses into generic dict to bind value param', () => {
		let b = doUnify(dict_(param_('T')), dict_(prim('boolean')));
		assert.match(prim('boolean'), b['T']);
	});

	it('does not bind on generic base mismatch', () => {
		let b = doUnify(list_(param_('T')), dict_(prim('int')));
		assert.match(0, length(keys(b)));
	});

	it('recurses into ref params', () => {
		let b = doUnify(ref('Generator', [param_('T')]), ref('Generator', [prim('string')]));
		assert.match(prim('string'), b['T']);
	});

	it('does not bind on ref name mismatch', () => {
		let b = doUnify(ref('Foo', [param_('T')]), ref('Bar', [prim('int')]));
		assert.match(0, length(keys(b)));
	});

	it('recurses into nullable inner', () => {
		let b = doUnify(nullable(param_('T')), nullable(prim('float')));
		assert.match(prim('float'), b['T']);
	});

	it('binds multiple params across a function signature', () => {
		let paramType = fn_([np('x', param_('T')), np('y', param_('U'))], param_('T'));
		let argType   = fn_([np('x', prim('string')), np('y', prim('int'))], prim('string'));
		let b = doUnify(paramType, argType);
		assert.match(prim('string'), b['T']);
		assert.match(prim('int'), b['U']);
	});

	it('accumulates bindings from multiple calls into one map', () => {
		// Caller accumulates across argument pairs.
		let bindings = {};
		unify(param_('T'), prim('string'), bindings, 0);
		unify(param_('U'), prim('int'),    bindings, 0);
		assert.match(prim('string'), bindings['T']);
		assert.match(prim('int'),    bindings['U']);
	});

	it('returns no bindings on primitive match', () => {
		let b = doUnify(prim('string'), prim('int'));
		assert.match(0, length(keys(b)));
	});

	it('does not overwrite an already-bound param', () => {
		let b = doUnify(union_(param_('T'), param_('T')), union_(prim('int'), prim('string')));
		assert.match(prim('int'), b['T']);
	});

	it('bails silently at depth > 5', () => {
		let b = {};
		unify(param_('T'), prim('string'), b, 6);
		assert.match(0, length(keys(b)));
	});
});

describe('substitute', () => {
	it('replaces a param node with its binding', () => {
		let result = substitute(param_('T'), { T: prim('string') });
		assert.match(prim('string'), result);
	});

	it('leaves unbound param unchanged', () => {
		let result = substitute(param_('T'), {});
		assert.match(param_('T'), result);
	});

	it('recurses into generic params', () => {
		let result = substitute(list_(param_('T')), { T: prim('int') });
		assert.match(list_(prim('int')), result);
	});

	it('recurses into dict generic', () => {
		let result = substitute(dict_(param_('T')), { T: prim('string') });
		assert.match(dict_(prim('string')), result);
	});

	it('recurses into nullable inner', () => {
		let result = substitute(nullable(param_('T')), { T: prim('float') });
		assert.match(nullable(prim('float')), result);
	});

	it('recurses into ref type params', () => {
		let result = substitute(ref('Generator', [param_('T')]), { T: prim('string') });
		assert.match(ref('Generator', [prim('string')]), result);
	});

	it('leaves a plain ref (no params) unchanged', () => {
		let result = substitute(ref('MyType'), { T: prim('string') });
		assert.match(ref('MyType'), result);
	});

	it('recurses into union members', () => {
		let result = substitute(union_(param_('T'), prim('null')), { T: prim('string') });
		assert.match(union_(prim('string'), prim('null')), result);
	});

	it('recurses into function params and return', () => {
		let t = fn_([np('x', param_('T'))], param_('T'));
		let result = substitute(t, { T: prim('int') });
		assert.match(fn_([np('x', prim('int'))], prim('int')), result);
	});

	it('leaves primitives and any unchanged', () => {
		assert.match(prim('string'), substitute(prim('string'), { T: prim('int') }));
		assert.match({ kind: 'any' }, substitute({ kind: 'any' }, { T: prim('int') }));
	});

	it('round-trips: unify then substitute resolves generic return type', () => {
		// @template T @param {list<T>} items @returns {T}
		// Called with list<string> → T = string → return = string
		let paramSig = fn_([np('items', list_(param_('T')))], param_('T'));
		let argSig   = fn_([np('items', list_(prim('string')))], param_('T'));
		let bindings = {};
		unify(paramSig, argSig, bindings, 0);
		let resolved = substitute(paramSig.return, bindings);
		assert.match(prim('string'), resolved);
	});
});
