import * as fs from 'fs';
import * as uloop from 'uloop';
import * as workspace from 'code_analysis.workspace';
import * as reporters from 'linter.reporters';
import { fanOut } from 'code_analysis.parallel';

// Resolve a (possibly relative) path to an absolute file:// URI, or null if the
// file cannot be resolved.
function toUri(path) {
	let abs = fs.realpath(path);
	return abs ? ('file://' + abs) : null;
}

// Diagnose the whole workspace across `jobs` worker processes.
//
// The parent builds the entire DAG + builtins and parses every file once
// (loadWorkspaceDocs), then fans the docs out to workers with `fanOut`. Each
// worker inherits the fully-built DAG and all parsed trees via copy-on-write —
// no re-parsing or re-indexing — and only runs the expensive per-file work
// (scopeMap + type inference) for its shard, streaming results back.
//
// Being a one-shot CLI, the linter owns the event loop here: it wraps the
// loop-agnostic `fanOut` in its own `uloop.init`/`run`, ending the loop from the
// completion callback. (The LSP shares `fanOut` but drives it on its own live
// loop instead — see language_server/handlers/diagnostic_reports.uc.)
function diagnoseWorkspaceParallel(config, jobs) {
	let docs = workspace.loadWorkspaceDocs(config);
	if (jobs > length(docs)) jobs = length(docs);
	if (jobs <= 1) {
		let results = [];
		for (let doc in docs)
			push(results, workspace.diagnoseDoc(doc));
		return results;
	}

	let results = [];
	uloop.init();
	fanOut(docs, jobs,
		(doc)  => workspace.diagnoseDoc(doc),
		(item) => push(results, item),
		()     => uloop.end());
	uloop.run();
	return results;
}

// One-shot lint. config carries workspaceDir / selfSrcDir / systemLibPaths just
// like the language server. opts:
//   files:  array of paths to lint, or null to scan the whole workspace
//   format: 'text' | 'json'
//   failOn: 'error' | 'warning' | 'info' | 'hint' | 'none'
//   jobs:   number of parallel worker processes for workspace mode (>=1)
// Returns the process exit code: 0 clean / below threshold, 1 findings at or
// above --fail-on, 2 usage or IO error.
export function run(config, opts) {
	if (opts.files === null) {
		let st = fs.stat(config.workspaceDir);
		if (!st || st.type !== 'directory') {
			warn(sprintf('ucode-linter: workspace not found: %s\n', config.workspaceDir));
			return 2;
		}
	}

	let results;
	if (opts.files !== null) {
		// File mode: build the cross-file graph so the listed files' imports
		// resolve against the whole workspace, then diagnose just those files.
		workspace.loadWorkspace(config);
		results = [];
		for (let path in opts.files) {
			let uri = toUri(path);
			if (!uri) {
				warn(sprintf('ucode-linter: cannot read file: %s\n', path));
				return 2;
			}
			push(results, { uri, diags: workspace.diagnoseFile(uri) });
		}
	} else if ((opts.jobs ?? 1) <= 1) {
		// Workspace mode, serial: single parse-once pass in this process.
		results = workspace.diagnoseWorkspace(config);
	} else {
		// Workspace mode, parallel: shard diagnosis across worker processes.
		results = diagnoseWorkspaceParallel(config, opts.jobs);
	}

	// Deterministic output regardless of worker scheduling.
	sort(results, (a, b) => (a.uri < b.uri) ? -1 : (a.uri > b.uri) ? 1 : 0);

	if (opts.format === 'json') {
		print(reporters.formatJson(results) + '\n');
	} else {
		let body = reporters.formatText(results, config.workspaceDir);
		if (length(body) > 0) print(body + '\n');
		warn(reporters.summary(results) + '\n');
	}

	return reporters.exitCode(results, opts.failOn);
};
