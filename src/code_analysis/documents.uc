import * as fs from 'fs';
import * as ts from 'tree_sitter';
import { buildLineTable } from 'code_analysis.positions';
import { buildScopeMap } from 'code_analysis.types.scope_walk';

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

// Read and parse a file from disk into a bare document (no lineTable/scopeMap).
// Returns null if the file can't be read. The scopeMap must be attached later
// with withScopeMap(), once the DAG is complete, because it resolves imports.
export function readParsed(uri) {
	let f = fs.open(substr(uri, 7), 'r');  // strip "file://"
	if (!f) return null;
	let text = f.read('all');
	f.close();
	return { uri, text, version: null, tree: ts.parse(_parser, text) };
};

// Attach lineTable + scopeMap to a bare document (from readParsed) and return
// it. Call once the DAG is fully populated so import-based types resolve.
export function withScopeMap(doc) {
	doc.lineTable = buildLineTable(doc.text);
	doc.scopeMap  = buildScopeMap(doc.uri, doc.text, doc.tree);
	return doc;
};

// Return the open document for uri, or — for a file that is not open in the
// editor — an ephemeral document read and parsed from disk. The ephemeral doc
// is NOT cached in _documents; it is meant for one-off use by the per-file
// diagnostics path (the DAG is already complete there). Returns null if the
// file can't be read.
export function getOrLoad(uri) {
	let doc = _documents[uri];
	if (doc) return doc;

	let parsed = readParsed(uri);
	return parsed ? withScopeMap(parsed) : null;
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
