import * as fs from 'fs';
import * as ts from 'tree_sitter';
import { buildLineTable } from 'language_server.positions';
import { buildScopeMap } from 'language_server.types.scope_walk';

let _parser = ts.newParser(ts.ucode());
let _documents = {};

export function open(uri, text, version) {
	let tree = ts.parse(_parser, text);
	_documents[uri] = {
		uri,
		text,
		version,
		tree,
		lineTable: buildLineTable(text),
		scopeMap: buildScopeMap(uri, text, tree),
	};
};

export function change(uri, changes, version) {
	let doc = _documents[uri];

	if (!doc || !length(changes))
		return;

	let text = changes[0].text;
	let tree = ts.parse(_parser, text);

	_documents[uri] = {
		uri,
		text,
		version,
		tree,
		lineTable: buildLineTable(text),
		scopeMap: buildScopeMap(uri, text, tree),
	};
};

export function get(uri) {
	return _documents[uri];
};

// Return the open document for uri, or — for a file that is not open in the
// editor — an ephemeral document read and parsed from disk. The ephemeral doc
// is NOT cached in _documents; it is meant for one-off use by the workspace
// diagnostics scan. Returns null if the file can't be read.
export function getOrLoad(uri) {
	let doc = _documents[uri];
	if (doc) return doc;

	let f = fs.open(substr(uri, 7), 'r');  // strip "file://"
	if (!f) return null;
	let text = f.read('all');
	f.close();

	let tree = ts.parse(_parser, text);
	return {
		uri,
		text,
		version: null,
		tree,
		lineTable: buildLineTable(text),
		scopeMap: buildScopeMap(uri, text, tree),
	};
};

export function refreshScopeMap(uri) {
	let doc = _documents[uri];
	if (doc) doc.scopeMap = buildScopeMap(uri, doc.text, doc.tree);
};

export function close(uri) {
	delete _documents[uri];
};

export function all() {
	return _documents;
};
