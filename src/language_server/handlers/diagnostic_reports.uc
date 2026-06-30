import * as uloop from 'uloop';
import * as protocol from 'language_server.protocol';
import * as documents from 'language_server.documents';
import * as dag from 'language_server.dag.dag';
import { diagnosticsFor } from 'language_server.handlers.diagnostics';

// Per-URI resultId generation. Bumped whenever a document's diagnostics may
// have changed (edit, dependency cascade, watched-file change). A pull request
// returns 'unchanged' while the client's previous resultId still matches, so
// re-pulls of untouched files are essentially free.
let _gen = {};

export function invalidate(uri) {
	_gen[uri] = (_gen[uri] ?? 0) + 1;
};

function resultId(uri) {
	return sprintf('%d', _gen[uri] ?? 0);
};

// --- textDocument/diagnostic (single open document, synchronous) ------------

export function documentDiagnostics(uri, doc, previousResultId) {
	let id = resultId(uri);
	if (previousResultId === id)
		return { kind: 'unchanged', resultId: id };
	return { kind: 'full', resultId: id, items: diagnosticsFor(uri, doc) };
};

// --- workspace/diagnostic (all workspace files, background fork) ------------

function isWorkspaceUri(uri, config) {
	let path = substr(uri, 7);  // strip "file://"
	let workdir = config.workspaceDir ?? '/';
	if (substr(path, 0, length(workdir)) !== workdir) return false;

	// Exclude the server's own bundled sources and any system library roots —
	// those are dependencies, not the user's workspace.
	let self = config.selfSrcDir;
	if (self && substr(path, 0, length(self)) === self) return false;
	for (let sp in (config.systemLibPaths ?? []))
		if (substr(path, 0, length(sp)) === sp) return false;

	// Declaration stubs are not diagnosed.
	if (length(path) >= 5 && substr(path, length(path) - 5) === '.d.uc') return false;

	return true;
};

let _activeTask = null;
let _pendingReqId = null;
let _report = [];

export function workspaceDiagnostics(requestId, params, config) {
	// A newer request supersedes any in-flight scan.
	if (_activeTask) {
		_activeTask.kill();
		_activeTask = null;
	}

	let prevIds = {};
	for (let r in (params.previousResultIds ?? []))
		prevIds[r.uri] = r.value;

	let uris = [];
	for (let uri in dag.allUris())
		if (isWorkspaceUri(uri, config))
			push(uris, uri);

	_pendingReqId = requestId;
	_report = [];

	// The child inherits the parent's full state at fork time (DAG, open
	// documents, resultId generations) and runs the scan synchronously without
	// blocking the parent's event loop. Results stream back over the pipe.
	_activeTask = uloop.task(
		function(pipe) {
			for (let uri in uris) {
				let id = resultId(uri);
				if (prevIds[uri] === id) {
					pipe.send({ kind: 'unchanged', uri, version: null, resultId: id });
					continue;
				}
				let doc = documents.getOrLoad(uri);
				let diags = doc ? diagnosticsFor(uri, doc) : [];
				pipe.send({ kind: 'full', uri, version: (doc ? doc.version : null), resultId: id, items: diags });
			}
		},
		function(item) {
			// A null item is uloop's task-completion sentinel.
			if (item === null) {
				protocol.respond(_pendingReqId, { items: _report });
				_activeTask = null;
				_pendingReqId = null;
				_report = [];
				return;
			}
			push(_report, item);
		}
	);
};
