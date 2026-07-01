import * as uloop from 'uloop';
import * as protocol from 'language_server.protocol';
import { diagnosticsFor } from 'code_analysis.diagnostics';
import { workspaceUris, diagnoseFile } from 'code_analysis.workspace';

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

// LSP error code: the request could not be served because the content changed.
// Clients treat it as "obsolete, re-request" rather than a hard failure.
let CONTENT_MODIFIED = -32801;

let _activeTask = null;
let _pendingReqId = null;
let _report = [];
// Bumped for every scan. A superseded task keeps running (kill() is not
// guaranteed to cancel its pending pipe callbacks), and its late items / sentinel
// would otherwise corrupt the successor's report or emit a duplicate response.
// Each task closes over its own generation and drops any callback that is no
// longer current.
let _scanGen = 0;

export function workspaceDiagnostics(requestId, params, config) {
	// A newer request supersedes any in-flight scan. The superseded task never
	// delivers a usable result, so the previous request id would otherwise never be
	// answered — the client's pending promise would leak. Abort it explicitly with
	// ContentModified so the client re-pulls.
	if (_pendingReqId !== null) {
		if (_activeTask) {
			_activeTask.kill();
			_activeTask = null;
		}
		protocol.error(_pendingReqId, CONTENT_MODIFIED,
			'workspace/diagnostic superseded by a newer request');
		_pendingReqId = null;
		_report = [];
	}

	let prevIds = {};
	for (let r in (params.previousResultIds ?? []))
		prevIds[r.uri] = r.value;

	let uris = workspaceUris(config);

	let myGen = ++_scanGen;
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
				pipe.send({ kind: 'full', uri, version: null, resultId: id, items: diagnoseFile(uri) });
			}
		},
		function(item) {
			// Ignore callbacks from a scan that has since been superseded — their
			// items must not leak into the current report and their sentinel must
			// not double-respond.
			if (myGen !== _scanGen) return;
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
