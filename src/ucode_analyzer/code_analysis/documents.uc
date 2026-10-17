import * as fs from 'fs';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { buildLineTable } from 'ucode_analyzer.code_analysis.positions';
import { buildScopeMap } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';

let _documents = {};

// An open document's scope map resolves its imports through the DAG, so it is
// built on first use: new text, or a change to a file it imports (markStale),
// only drops it, and get() rebuilds it. The caller can then update the DAG
// first, and a burst of edits costs one rebuild.
// The type caches are keyed by byte ranges, not content: any new text for a
// uri must drop them, or a same-length text would read stale entries.
function store(uri, text, version) {
	invalidateUri(uri);
	let doc = {
		uri,
		text,
		version,
		tree: mode.parse(text),
		lineTable: buildLineTable(text),
		scopeMap: null,
	};
	_documents[uri] = doc;
	return doc;
}

// Store an opened document; returns it, without its scope map.
export function open(uri, text, version) {
	return store(uri, text, version);
};

// Replace an open document's text; returns it, without its scope map, or null
// if the document is not open.
export function change(uri, changes, version) {
	if (!_documents[uri] || !length(changes))
		return null;
	return store(uri, changes[0].text, version);
};

// The open document for uri, with its scope map; null if it is not open.
export function get(uri) {
	let doc = _documents[uri];
	if (doc && !doc.scopeMap)
		doc.scopeMap = buildScopeMap(uri, doc.text, doc.tree);
	return doc;
};

export function isOpen(uri) {
	return exists(_documents, uri);
};

// The version of an open document; null if it is not open.
export function versionOf(uri) {
	return _documents[uri]?.version ?? null;
};

// Drop the scope map of an open document whose imports changed.
export function markStale(uri) {
	let doc = _documents[uri];
	if (doc) doc.scopeMap = null;
};

// Read and parse a file from disk into a bare document (no lineTable/scopeMap).
// Returns null if the file can't be read. The scopeMap must be attached later
// with withScopeMap(), once the DAG is complete, because it resolves imports.
export function readParsed(uri) {
	let f = fs.open(substr(uri, 7), 'r');  // strip "file://"
	if (!f) return null;
	let text = f.read('all');
	f.close();
	return { uri, text, version: null, tree: mode.parse(text) };
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
	let doc = get(uri);
	if (doc) return doc;

	let parsed = readParsed(uri);
	return parsed ? withScopeMap(parsed) : null;
};

export function close(uri) {
	invalidateUri(uri);
	delete _documents[uri];
};

// Every open document, as stored: scope maps may be missing.
export function all() {
	return _documents;
};
