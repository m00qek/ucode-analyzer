import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';

describe('documents', () => {
	afterEach(() => {
		documents.close('file:///x.uc');
	});

	it('open() stores uri, text, version, tree, and lineTable', () => {
		documents.open('file:///x.uc', 'let x = 5;', 1);
		let doc = documents.get('file:///x.uc');

		assert.match('file:///x.uc', doc.uri);
		assert.match('let x = 5;', doc.text);
		assert.match(1, doc.version);
		assert.match(true, doc.tree !== null);
		assert.match([0], doc.lineTable);
	});

	it('change() updates text, version, tree, and lineTable', () => {
		documents.open('file:///x.uc', 'let x = 5;', 1);
		documents.change('file:///x.uc', [{ text: 'let x = 5;\nlet y = 6;' }], 2);
		let doc = documents.get('file:///x.uc');

		assert.match('let x = 5;\nlet y = 6;', doc.text);
		assert.match(2, doc.version);
		assert.match([0, 11], doc.lineTable);
	});

	it('change() on unknown uri is a no-op', () => {
		documents.change('file:///nope.uc', [{ text: 'x' }], 1);
		assert.match(null, documents.get('file:///nope.uc'));
	});

	it('close() removes the document', () => {
		documents.open('file:///x.uc', 'x', 1);
		documents.close('file:///x.uc');
		assert.match(null, documents.get('file:///x.uc'));
	});

	it('get() returns null for unknown uri', () => {
		assert.match(null, documents.get('file:///unknown.uc'));
	});
});
