import * as protocol from 'language_server.protocol';
import { diagnosticsFor } from 'code_analysis.diagnostics';
import { workspaceUris, diagnoseFile } from 'code_analysis.workspace';
import { fanOut, detectJobs } from 'code_analysis.parallel';

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
let REQUEST_CANCELLED = -32800;

// The forked workers of the current scan (one per shard). Held so a supersede or
// teardown can kill every one of them, not just a single task.
let _activeTasks = [];
let _pendingReqId = null;
let _report = [];
// Bumped for every scan. A superseded worker keeps running (kill() is not
// guaranteed to cancel its pending pipe callbacks), and its late items / sentinel
// would otherwise corrupt the successor's report or emit a duplicate response.
// Every worker's onItem/onDone closes over its scan's generation and drops any
// callback that is no longer current — so a stale sentinel can neither tick the
// successor's completion counter (each fanOut owns its own counter) nor respond.
let _scanGen = 0;

function killAll() {
	for (let t in _activeTasks) t.kill();
	_activeTasks = [];
}

export function workspaceDiagnostics(requestId, params, config) {
	// A newer request supersedes any in-flight scan. The superseded workers never
	// deliver a usable result, so the previous request id would otherwise never be
	// answered — the client's pending promise would leak. Abort it explicitly with
	// ContentModified so the client re-pulls.
	if (_pendingReqId !== null) {
		killAll();
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

	// Shard the files across worker processes (batch work is the one place the
	// design permits using more than the 2-core floor). Each worker inherits the
	// parent's full state at fork time (DAG, open documents, resultId generations)
	// via copy-on-write and diagnoses its shard without blocking the parent's event
	// loop; results stream back and the report is sent once every worker completes.
	// Order within the report is not significant — each item carries its own uri.
	_activeTasks = fanOut(
		uris, detectJobs(),
		function(uri) {
			let id = resultId(uri);
			if (prevIds[uri] === id)
				return { kind: 'unchanged', uri, version: null, resultId: id };
			return { kind: 'full', uri, version: null, resultId: id, items: diagnoseFile(uri) };
		},
		function(item) {
			// Drop items from a scan that has since been superseded.
			if (myGen !== _scanGen) return;
			push(_report, item);
		},
		function() {
			// Drop the completion of a superseded scan — it must not double-respond.
			if (myGen !== _scanGen) return;
			protocol.respond(_pendingReqId, { items: _report });
			_activeTasks = [];
			_pendingReqId = null;
			_report = [];
		}
	);
};

// $/cancelRequest: stop the scan serving request `id`, if any, and answer it as
// cancelled. Returns whether there was one.
export function cancelRequest(id) {
	if (id === null || id !== _pendingReqId) return false;
	killAll();
	_scanGen += 1;
	protocol.error(id, REQUEST_CANCELLED, 'workspace/diagnostic cancelled');
	_pendingReqId = null;
	_report = [];
	return true;
};

// Kill an in-flight background scan on server teardown so the forked children are
// not orphaned. The scan generation is bumped so any late callback from a killed
// worker is ignored. We are exiting, so the pending request is left unanswered
// (the client is going away too).
export function cancel() {
	killAll();
	_scanGen += 1;
	_pendingReqId = null;
	_report = [];
};
