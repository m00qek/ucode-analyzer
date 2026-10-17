import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as fixture from 'fixture';

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
		assert.match(null, documents.change('file:///nope.uc', [{ text: 'x' }], 1));
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

	it('builds the scope map on first get(), not on open() or change()', () => {
		let opened = documents.open('file:///x.uc', 'let x = 5;', 1);
		assert.match(null, opened.scopeMap);
		assert.match(true, documents.get('file:///x.uc').scopeMap !== null);
		let changed = documents.change('file:///x.uc', [{ text: 'let y = 6;' }], 2);
		assert.match(null, changed.scopeMap);
		assert.match(true, documents.get('file:///x.uc').scopeMap !== null);
	});

	it('markStale() makes the next get() rebuild the scope map', () => {
		documents.open('file:///x.uc', 'let x = 5;', 1);
		let first = documents.get('file:///x.uc').scopeMap;
		assert.match(true, documents.get('file:///x.uc').scopeMap === first);
		documents.markStale('file:///x.uc');
		let rebuilt = documents.get('file:///x.uc').scopeMap;
		assert.match(true, rebuilt !== null && rebuilt !== first);
	});

	it('versionOf() gives the version of an open document', () => {
		documents.open('file:///x.uc', 'x', 3);
		assert.match(3, documents.versionOf('file:///x.uc'));
		assert.match(null, documents.versionOf('file:///unknown.uc'));
	});

	it('isOpen() reports open documents without building their scope map', () => {
		let doc = documents.open('file:///x.uc', 'x', 1);
		assert.match(true, documents.isOpen('file:///x.uc'));
		assert.match(null, doc.scopeMap);
		assert.match(false, documents.isOpen('file:///unknown.uc'));
	});
});

describe('documents — getOrRead', () => {
	it('gives the open document when there is one', () => {
		let uri = fixture.uri('greet.uc');
		documents.open(uri, 'let open = 1;', 3);
		let doc = documents.getOrRead(uri);
		documents.close(uri);
		assert.match('let open = 1;', doc.text);
		assert.match(3, doc.version);
	});

	it('reads a file that is not open, without a scope map', () => {
		let doc = documents.getOrRead(fixture.uri('greet.uc'));
		assert.match(fixture.read('greet.uc'), doc.text);
		assert.match(length(split(doc.text, "\n")), length(doc.lineTable));
		assert.match(null, doc.scopeMap);
		assert.match(false, documents.isOpen(fixture.uri('greet.uc')));
	});

	it('gives null for a file that cannot be read', () => {
		assert.match(null, documents.getOrRead(fixture.uri('missing.uc')));
	});
});
