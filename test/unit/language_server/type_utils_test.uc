import { describe, it, assert, beforeEach } from 'utest';
import { UNKNOWN, STR, INT, unionOf, memberOfType } from 'ucode_language_server.types.type_utils';
import * as registry from 'ucode_language_server.types.registry';

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

	it('returns a union for two distinct primitives', () => {
		let r = unionOf([INT, STR]);
		assert.match('union', r.kind);
		assert.match(2, length(r.members));
	});

	it('deduplicates within a union — three items two distinct', () => {
		let r = unionOf([INT, STR, INT]);
		assert.match('union', r.kind);
		assert.match(2, length(r.members));
	});

	it('preserves non-primitive types (record) as distinct entries', () => {
		let rec = { kind: 'record', fields: [] };
		let r = unionOf([INT, rec]);
		assert.match('union', r.kind);
		assert.match(2, length(r.members));
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
		let r = memberOfType(u, 'v');
		assert.match('union', r.kind);
		assert.match(2, length(r.members));
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
