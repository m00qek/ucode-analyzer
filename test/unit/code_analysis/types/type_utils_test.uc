import { describe, it, assert, beforeEach } from 'utest';
import { UNKNOWN, STR, INT, unionOf, memberOfType, resolveRef, literal, widen } from 'ucode_analyzer.code_analysis.types.type_utils';
import * as registry from 'ucode_analyzer.code_analysis.types.registry';

beforeEach(() => {
	// Remove all registered types so ref-lookup tests start clean.
	for (let name in registry.allNames()) {
		let e = registry.lookup(name);
		if (e) registry.removeUri(e.sourceUri);
	}
});

describe('type_utils.unionOf', () => {
	it('returns UNKNOWN for empty list', () => {
		assert.match({ kind: 'unknown' }, unionOf([]));
	});

	it('returns the sole element unchanged for a singleton list', () => {
		assert.match(INT, unionOf([INT]));
	});

	it('deduplicates identical primitive types', () => {
		assert.match(INT, unionOf([INT, INT, INT]));
	});

	it('flattens nested unions', () => {
		let NUL = { kind: 'primitive', name: 'null' };
		let r = unionOf([unionOf([unionOf([STR, NUL]), NUL]), INT]);
		assert.match({ kind: 'union', members: [STR, NUL, INT] }, r);
	});

	it('returns a union for two distinct primitives', () => {
		assert.match({ kind: 'union', members: [INT, STR] }, unionOf([INT, STR]));
	});

	it('deduplicates within a union — three items two distinct', () => {
		assert.match({ kind: 'union', members: [INT, STR] }, unionOf([INT, STR, INT]));
	});

	it('preserves non-primitive types (record) as distinct entries', () => {
		let rec = { kind: 'record', fields: [] };
		assert.match({ kind: 'union', members: [INT, rec] }, unionOf([INT, rec]));
	});

	it('keeps records with different field-name sets distinct', () => {
		let pass = { kind: 'record', fields: [{ name: 'kind', type: STR }] };
		let fail = { kind: 'record', fields: [
			{ name: 'kind', type: STR }, { name: 'value', type: INT },
		]};
		assert.match({ kind: 'union', members: [pass, fail] }, unionOf([pass, fail]));
	});

	it('merges records with the same field-name set, field by field', () => {
		let a = { kind: 'record', fields: [{ name: 'kind', type: STR }] };
		let b = { kind: 'record', fields: [{ name: 'kind', type: INT }] };
		assert.match({ kind: 'record', fields: [{ name: 'kind', type: { kind: 'union', members: [STR, INT] } }] },
			unionOf([a, b]));
	});

	it('keeps a merged record open if either is', () => {
		let a = { kind: 'record', fields: [{ name: 'x', type: INT }] };
		let b = { kind: 'record', fields: [{ name: 'x', type: INT }], open: true };
		assert.match({ kind: 'record', fields: [{ name: 'x', type: INT }], open: true }, unionOf([a, b]));
	});

	it('is order-insensitive when comparing field names', () => {
		let a = { kind: 'record', fields: [{ name: 'x', type: INT }, { name: 'y', type: STR }] };
		let b = { kind: 'record', fields: [{ name: 'y', type: STR }, { name: 'x', type: INT }] };
		assert.match(a, unionOf([a, b]));
	});

	it('keeps distinct string literals apart', () => {
		let a = literal('string', 'a'), b = literal('string', 'b');
		assert.match({ kind: 'union', members: [a, b] }, unionOf([a, b]));
	});

	it('collapses equal string literals', () => {
		assert.match({ kind: 'primitive', name: 'string', value: 'a' },
		             unionOf([literal('string', 'a'), literal('string', 'a')]));
	});

	it('widens a literal unioned with its own base to the base', () => {
		assert.match(STR, unionOf([literal('string', 'a'), STR]));
		assert.match(STR, unionOf([STR, literal('string', 'a')]));
	});
});

describe('type_utils.widen', () => {
	it('strips the value from a literal, leaving the base primitive', () => {
		assert.match(STR, widen(literal('string', 'fail')));
	});

	it('leaves a non-literal primitive unchanged', () => {
		assert.match(INT, widen(INT));
	});
});

describe('type_utils.memberOfType', () => {
	it('returns UNKNOWN for null type', () => {
		assert.match({ kind: 'unknown' }, memberOfType(null, 'foo'));
	});

	it('returns UNKNOWN for unknown type', () => {
		assert.match({ kind: 'unknown' }, memberOfType(UNKNOWN, 'foo'));
	});

	it('looks up a field in a record type', () => {
		let rec = { kind: 'record', fields: [
			{ name: 'x', type: INT },
			{ name: 'y', type: STR },
		]};
		assert.match(INT, memberOfType(rec, 'x'));
		assert.match(STR, memberOfType(rec, 'y'));
	});

	it('returns UNKNOWN for a missing field in a record', () => {
		let rec = { kind: 'record', fields: [{ name: 'x', type: INT }] };
		assert.match({ kind: 'unknown' }, memberOfType(rec, 'z'));
	});

	it('unwraps nullable before lookup', () => {
		let rec = { kind: 'record', fields: [{ name: 'n', type: INT }] };
		let nullable = { kind: 'nullable', inner: rec };
		assert.match(INT, memberOfType(nullable, 'n'));
	});

	it('returns union of matching fields from union members', () => {
		let recA = { kind: 'record', fields: [{ name: 'v', type: INT }] };
		let recB = { kind: 'record', fields: [{ name: 'v', type: STR }] };
		let u = { kind: 'union', members: [recA, recB] };
		assert.match({ kind: 'union', members: [INT, STR] }, memberOfType(u, 'v'));
	});

	it('resolves a ref type through the registry', () => {
		let rec = { kind: 'record', fields: [{ name: 'id', type: INT }] };
		registry.register('MyType', rec, 'file:///a.uc');
		let ref = { kind: 'ref', name: 'MyType' };
		assert.match(INT, memberOfType(ref, 'id'));
	});

	it('returns UNKNOWN for an unregistered ref', () => {
		let ref = { kind: 'ref', name: 'NoSuchType' };
		assert.match({ kind: 'unknown' }, memberOfType(ref, 'x'));
	});
});

describe('type_utils.resolveRef', () => {
	let FN = { kind: 'function', params: [], return: UNKNOWN };

	it('returns a non-ref type unchanged', () => {
		assert.match(INT, resolveRef(INT));
	});

	it('resolves a ref to its registered target', () => {
		registry.register('Callback', FN, 'file:///a.uc');
		assert.match(FN, resolveRef({ kind: 'ref', name: 'Callback' }));
	});

	it('follows a chain of refs to the concrete type', () => {
		registry.register('A', { kind: 'ref', name: 'B' }, 'file:///a.uc');
		registry.register('B', INT, 'file:///a.uc');
		assert.match(INT, resolveRef({ kind: 'ref', name: 'A' }));
	});

	it('substitutes @template params into the target', () => {
		// @template T ; @typedef {{ v: T }} Box<T>
		let box = { kind: 'record', fields: [{ name: 'v', type: { kind: 'param', name: 'T' } }] };
		registry.register('Box', box, 'file:///a.uc', ['T']);
		let resolved = resolveRef({ kind: 'ref', name: 'Box', params: [STR] });
		assert.match({ kind: 'record', fields: [{ name: 'v', type: STR }] }, resolved);
	});

	it('returns the ref unchanged when unregistered', () => {
		let ref = { kind: 'ref', name: 'Missing' };
		assert.match({ kind: 'ref', name: 'Missing' }, resolveRef(ref));
	});

	it('terminates on a self-referential cycle', () => {
		registry.register('Loop', { kind: 'ref', name: 'Loop' }, 'file:///a.uc');
		assert.match({ kind: 'ref', name: 'Loop' }, resolveRef({ kind: 'ref', name: 'Loop' }));
	});
});
