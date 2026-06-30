import * as glob from 'language_server.glob';
import * as dag from 'language_server.dag.dag';
import * as documents from 'language_server.documents';
import { initBuiltinsFromDag } from 'language_server.types.inferrer';
import { diagnosticsFor } from 'language_server.handlers.diagnostics';

// Build the cross-file graph and the builtin scope for a workspace: index every
// library / declaration / system-lib file into the DAG and initialise builtins.
// Returns the declaration @version map ({ uri -> versions[] }) so the caller can
// decide whether and how to initialise platform availability.
//
// Imports only analysis modules (no protocol/io/uloop), so it is shared by both
// the language server (`initialized`) and the standalone linter.
export function loadWorkspace(config) {
	let workspaceDir = config.workspaceDir ?? '/root/project';
	let ws = config.workspace ?? {};
	let libPaths = ws.libraryPaths ?? ['src'];

	dag.init(config);

	for (let relPath in libPaths) {
		let files = glob.scan(workspaceDir + '/' + relPath, ['**/*.uc'], []);
		for (let path in files)
			dag.addFromDisk('file://' + path);
	}

	if (config.selfSrcDir) {
		let files = glob.scan(config.selfSrcDir + '/declarations', ['**/*.uc'], []);
		for (let path in files)
			dag.addFromDisk('file://' + path);
	}

	for (let sysPath in (config.systemLibPaths ?? [])) {
		let files = glob.scan(sysPath, ['**/*.uc'], []);
		for (let path in files)
			dag.addFromDisk('file://' + path);
	}

	let globalUri = dag.resolveSpecifier('global');
	if (globalUri) initBuiltinsFromDag(globalUri);

	let declVersions = {};
	for (let uri in dag.allUris()) {
		if (index(uri, '.d.uc') < 0) continue;
		let v = dag.versionsOf(uri);
		if (v) declVersions[uri] = v;
	}
	return declVersions;
};

// A URI is part of the user's workspace when its path is under workspaceDir and
// is not one of the server's own bundled sources, a system library, or a
// declaration stub (those are dependencies, not files we diagnose).
function isWorkspaceUri(uri, config) {
	let path = substr(uri, 7);  // strip "file://"
	let workdir = config.workspaceDir ?? '/';
	if (substr(path, 0, length(workdir)) !== workdir) return false;

	let self = config.selfSrcDir;
	if (self && substr(path, 0, length(self)) === self) return false;
	for (let sp in (config.systemLibPaths ?? []))
		if (substr(path, 0, length(sp)) === sp) return false;

	if (length(path) >= 5 && substr(path, length(path) - 5) === '.d.uc') return false;

	return true;
};

// Every workspace URI currently known to the DAG.
export function workspaceUris(config) {
	let uris = [];
	for (let uri in dag.allUris())
		if (isWorkspaceUri(uri, config))
			push(uris, uri);
	return uris;
};

// Diagnose a single URI, loading it from disk if it is not open.
export function diagnoseFile(uri) {
	let doc = documents.getOrLoad(uri);
	return doc ? diagnosticsFor(uri, doc) : [];
};

// Load the workspace and diagnose every workspace file in a single pass that
// reads and parses each file exactly once: the parsed tree is reused for both
// DAG indexing and diagnosis, instead of parsing once to index (loadWorkspace)
// and again to diagnose (getOrLoad). Returns [{ uri, diags }]. Used by the
// linter's workspace mode.
export function diagnoseWorkspace(config) {
	let workspaceDir = config.workspaceDir ?? '/root/project';
	let ws = config.workspace ?? {};
	let libPaths = ws.libraryPaths ?? ['src'];

	dag.init(config);

	// Phase 1: parse each workspace file once, index it from that parse, and keep
	// the bare doc. The scopeMap is deliberately NOT built yet — it resolves
	// imports, so it must wait until the whole DAG is populated.
	let docs = [];
	let seen = {};
	for (let relPath in libPaths) {
		for (let path in glob.scan(workspaceDir + '/' + relPath, ['**/*.uc'], [])) {
			let uri = 'file://' + path;
			if (seen[uri]) continue;
			seen[uri] = true;
			let doc = documents.readParsed(uri);
			if (!doc) continue;
			dag.add(uri, doc.text, doc.tree);
			push(docs, doc);
		}
	}

	// Index dependencies we resolve against but never diagnose (declaration
	// stubs, system libraries): a single parse-and-discard is enough.
	if (config.selfSrcDir)
		for (let path in glob.scan(config.selfSrcDir + '/declarations', ['**/*.uc'], [])) {
			let uri = 'file://' + path;
			if (seen[uri]) continue;
			seen[uri] = true;
			dag.addFromDisk(uri);
		}
	for (let sysPath in (config.systemLibPaths ?? []))
		for (let path in glob.scan(sysPath, ['**/*.uc'], [])) {
			let uri = 'file://' + path;
			if (seen[uri]) continue;
			seen[uri] = true;
			dag.addFromDisk(uri);
		}

	let globalUri = dag.resolveSpecifier('global');
	if (globalUri) initBuiltinsFromDag(globalUri);

	// Phase 2: the DAG is complete — build each workspace doc's scopeMap and
	// diagnose it.
	let results = [];
	for (let doc in docs) {
		if (!isWorkspaceUri(doc.uri, config)) continue;
		documents.withScopeMap(doc);
		push(results, { uri: doc.uri, diags: diagnosticsFor(doc.uri, doc) });
	}
	return results;
};
