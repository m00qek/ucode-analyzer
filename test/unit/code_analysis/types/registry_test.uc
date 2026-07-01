import { describe, it, assert, beforeEach } from 'utest';
import * as reg from 'code_analysis.types.registry';

let T_STRING = { kind: 'primitive', name: 'string' };
let T_INT    = { kind: 'primitive', name: 'int' };

describe('type_registry', () => {
	beforeEach(() => {
		let seen = {};
		for (let name in reg.allNames()) {
			let entry = reg.lookup(name);
			if (entry && !seen[entry.sourceUri]) {
				seen[entry.sourceUri] = true;
				reg.removeUri(entry.sourceUri);
			}
		}
	});

	it('register and lookup by name', () => {
		reg.register('MyId', T_STRING, 'file:///a.uc');
		let entry = reg.lookup('MyId');
		assert.match(T_STRING, entry.type);
		assert.match('file:///a.uc', entry.sourceUri);
	});

	it('lookup returns null for unknown name', () => {
		assert.match(null, reg.lookup('Unknown'));
	});

	it('allNames returns registered names', () => {
		reg.register('Foo', T_STRING, 'file:///a.uc');
		reg.register('Bar', T_INT, 'file:///b.uc');
		let names = reg.allNames();
		assert.match(true, index(names, 'Foo') >= 0);
		assert.match(true, index(names, 'Bar') >= 0);
	});

	it('removeUri clears all entries from that file', () => {
		reg.register('Foo', T_STRING, 'file:///a.uc');
		reg.register('Bar', T_INT, 'file:///a.uc');
		reg.register('Baz', T_STRING, 'file:///b.uc');

		reg.removeUri('file:///a.uc');

		assert.match(null, reg.lookup('Foo'));
		assert.match(null, reg.lookup('Bar'));
		assert.match(true, reg.lookup('Baz') !== null);
	});

	it('register overwrites an existing entry', () => {
		reg.register('MyId', T_STRING, 'file:///a.uc');
		reg.register('MyId', T_INT, 'file:///b.uc');
		assert.match(T_INT, reg.lookup('MyId').type);
	});
});
