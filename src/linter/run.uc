import * as fs from 'fs';
import * as workspace from 'language_server.workspace';
import * as reporters from 'linter.reporters';

// Resolve a (possibly relative) path to an absolute file:// URI, or null if the
// file cannot be resolved.
function toUri(path) {
	let abs = fs.realpath(path);
	return abs ? ('file://' + abs) : null;
}

// One-shot lint. config carries workspaceDir / selfSrcDir / systemLibPaths just
// like the language server. opts:
//   files:  array of paths to lint, or null to scan the whole workspace
//   format: 'text' | 'json'
//   failOn: 'error' | 'warning' | 'info' | 'hint' | 'none'
// Returns the process exit code: 0 clean / below threshold, 1 findings at or
// above --fail-on, 2 usage or IO error.
export function run(config, opts) {
	// Build the cross-file graph + builtins. Even in file mode the imports in a
	// target file resolve against the whole workspace DAG.
	if (opts.files === null) {
		let st = fs.stat(config.workspaceDir);
		if (!st || st.type !== 'directory') {
			warn(sprintf('ucode-linter: workspace not found: %s\n', config.workspaceDir));
			return 2;
		}
	}

	workspace.loadWorkspace(config);

	let results;
	if (opts.files !== null) {
		results = [];
		for (let path in opts.files) {
			let uri = toUri(path);
			if (!uri) {
				warn(sprintf('ucode-linter: cannot read file: %s\n', path));
				return 2;
			}
			push(results, { uri, diags: workspace.diagnoseFile(uri) });
		}
	} else {
		results = workspace.collectWorkspaceDiagnostics(config);
	}

	if (opts.format === 'json') {
		print(reporters.formatJson(results) + '\n');
	} else {
		let body = reporters.formatText(results, config.workspaceDir);
		if (length(body) > 0) print(body + '\n');
		warn(reporters.summary(results) + '\n');
	}

	return reporters.exitCode(results, opts.failOn);
};
