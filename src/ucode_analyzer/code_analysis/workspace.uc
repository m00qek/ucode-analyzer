import * as glob from 'ucode_analyzer.code_analysis.glob';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { diagnosticsFor } from 'ucode_analyzer.code_analysis.diagnostics';
import { libraryDirs } from 'ucode_analyzer.code_analysis.config';
import { toPath } from 'ucode_analyzer.code_analysis.uri';
import { fanOut } from 'ucode_analyzer.code_analysis.parallel';

// Directories under workspaceDir that carry their own .lsp/config.json. Each is
// a self-contained nested workspace (e.g. the linter's test fixtures) and is
// diagnosed on its own terms, not as part of the parent — so the parent scan
// skips it. The parent's own config (at workspaceDir/.lsp/config.json) does not
// count. Computed once per scan and passed to isWorkspaceUri.
function nestedWorkspaceRoots(config) {
	let workdir = config.workspaceDir ?? '/';
	let suffix = '/.lsp/config.json';
	let roots = [];
	for (let cfg in glob.scan(workdir, ['**/.lsp/config.json'], [])) {
		if (substr(cfg, length(cfg) - length(suffix)) !== suffix) continue;
		let root = substr(cfg, 0, length(cfg) - length(suffix));
		if (root !== workdir && root !== '')
			push(roots, root + '/');
	}
	return roots;
};

// True when `path` is `dir` itself or lies beneath it, respecting the path
// separator so `/app-lib` is not considered under `/app`. A plain substr-prefix
// check (no boundary) would misclassify a sibling directory sharing a name
// prefix. A trailing slash on `dir` is tolerated (nested-root entries carry one).
function isUnder(path, dir) {
	if (dir === '') return false;
	if (length(dir) > 1 && substr(dir, length(dir) - 1) === '/')
		dir = substr(dir, 0, length(dir) - 1);
	if (dir === '/') return substr(path, 0, 1) === '/';
	if (path === dir) return true;
	return substr(path, 0, length(dir) + 1) === (dir + '/');
};

// Never a project's ucode sources: hidden folders (.git, tool and editor
// state) and npm dependencies. `workspace.exclude` adds to these.
const ALWAYS_EXCLUDED = ['**/.*/**', '**/node_modules/**'];

function excludes(config) {
	return [...ALWAYS_EXCLUDED, ...(config.workspace?.exclude ?? [])];
}

// Absolute paths of the files to index: the workspace's .uc files that no
// exclude matches, and those of library paths outside the workspace.
function sourceFiles(config) {
	let workdir = config.workspaceDir ?? '/root/project';
	let files = glob.scan(workdir, ['**/*.uc'], excludes(config));
	for (let dir in libraryDirs(config))
		if (!isUnder(dir, workdir))
			push(files, ...glob.scan(dir, ['**/*.uc'], []));
	return files;
}

// A URI is part of the user's workspace when its path is under workspaceDir and
// is not a system library, a declaration stub, a nested workspace or excluded
// (those are dependencies or separate projects, not files we diagnose here).
// The server's own sources are only ever in a workspace as a checkout being
// worked on: installed, they are a system library.
export function isWorkspaceUri(uri, config, nestedRoots) {
	let path = toPath(uri);
	let workdir = config.workspaceDir ?? '/';
	if (!isUnder(path, workdir)) return false;

	for (let sp in (config.systemLibPaths ?? []))
		if (isUnder(path, sp)) return false;

	for (let root in (nestedRoots ?? []))
		if (isUnder(path, root)) return false;

	if (length(path) >= 5 && substr(path, length(path) - 5) === '.d.uc') return false;

	let rel = (workdir === '/') ? substr(path, 1) : substr(path, length(workdir) + 1);
	for (let pattern in excludes(config))
		if (glob.matchPattern(pattern, rel)) return false;

	return true;
};

// The URIs to index, each once: the workspace's sources, then the declaration
// stubs and the system libraries.
function indexedUris(config) {
	let paths = sourceFiles(config);
	if (config.selfSrcDir)
		push(paths, ...glob.scan(config.selfSrcDir + '/declarations', ['**/*.uc'], []));
	for (let sysPath in (config.systemLibPaths ?? []))
		push(paths, ...glob.scan(sysPath, ['**/*.uc'], []));
	return uniq(map(paths, (p) => 'file://' + p));
}

// Once everything is indexed: the builtin scope, and the declaration @version
// map ({ uri -> versions[] }) for platform availability.
function finishLoad() {
	let globalUri = dag.resolveSpecifier('global');
	if (globalUri) initBuiltinsFromDag(globalUri);

	let declVersions = {};
	for (let uri in dag.allUris()) {
		if (index(uri, '.d.uc') < 0) continue;
		let v = dag.versionsOf(uri);
		if (v) declVersions[uri] = v;
	}
	return declVersions;
}

// Build the cross-file graph and the builtin scope for a workspace: index every
// source / declaration / system-lib file into the DAG and initialise builtins.
// Returns the declaration @version map.
export function loadWorkspace(config) {
	dag.init(config);
	for (let uri in indexedUris(config))
		dag.addFromDisk(uri);
	return finishLoad();
};

// As loadWorkspace, but the files are parsed and indexed by `jobs` forked
// workers on the current event loop, which stays free meanwhile. The DAG
// gets the results in one go, in loadWorkspace's order, and then onDone
// receives the @version map. Files indexed in-process before that (opened,
// changed on disk) keep that newer index. Returns the workers, to kill().
export function loadWorkspaceAsync(config, jobs, onDone) {
	dag.init(config);
	dag.beginLoad();
	let uris = indexedUris(config);
	let byUri = {};
	return fanOut(uris, jobs, dag.readRecord,
		(entry) => { if (entry) byUri[entry.uri] = entry; },
		() => {
			dag.endLoad(map(uris, (u) => byUri[u]));
			onDone(finishLoad());
		});
};

// Every workspace URI currently known to the DAG.
export function workspaceUris(config) {
	let nested = nestedWorkspaceRoots(config);
	let uris = [];
	for (let uri in dag.allUris())
		if (isWorkspaceUri(uri, config, nested))
			push(uris, uri);
	return uris;
};

// Diagnose a single URI, loading it from disk if it is not open.
export function diagnoseFile(uri) {
	// A single pathological file must never abort a workspace scan. diagnosticsFor
	// already isolates each pass; this also covers loading/parsing failures.
	try {
		let doc = documents.getOrLoad(uri);
		return doc ? diagnosticsFor(uri, doc) : [];
	} catch (e) {
		warn(sprintf("ucode-analyzer: failed to diagnose %s: %s\n", uri, e));
		return [];
	}
};

// Build the DAG + builtins and return the bare (un-scoped) workspace documents,
// each read and parsed exactly once: the parsed tree is reused for both DAG
// indexing and later diagnosis, instead of parsing once to index (loadWorkspace)
// and again to diagnose (getOrLoad). Shared setup for the serial and parallel
// workspace scans. The returned docs have no scopeMap yet — call diagnoseDoc()
// (which attaches it) once this has returned and the DAG is therefore complete.
export function loadWorkspaceDocs(config) {
	dag.init(config);

	// Parse each workspace file once, index it from that parse, and keep the bare
	// doc. The scopeMap is deliberately NOT built yet — it resolves imports, so it
	// must wait until the whole DAG is populated.
	let docs = [];
	let seen = {};
	for (let path in sourceFiles(config)) {
		let uri = 'file://' + path;
		if (seen[uri]) continue;
		seen[uri] = true;
		let doc = documents.readParsed(uri);
		if (!doc) continue;
		dag.add(uri, doc.text, doc.tree);
		push(docs, doc);
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

	let nested = nestedWorkspaceRoots(config);
	let out = [];
	for (let doc in docs)
		if (isWorkspaceUri(doc.uri, config, nested))
			push(out, doc);
	return out;
};

// Build a bare doc's scopeMap and diagnose it. Must be called after the DAG is
// complete (i.e. after loadWorkspaceDocs has returned), because the scopeMap
// resolves imports. Returns { uri, diags }.
export function diagnoseDoc(doc) {
	// As diagnoseFile, but for the parse-once scan path: also isolate a failure in
	// withScopeMap (scope walk / inference on a pathological tree) so one bad file
	// cannot abort a forked worker's whole shard.
	try {
		documents.withScopeMap(doc);
		return { uri: doc.uri, diags: diagnosticsFor(doc.uri, doc) };
	} catch (e) {
		warn(sprintf("ucode-analyzer: failed to diagnose %s: %s\n", doc.uri, e));
		return { uri: doc.uri, diags: [] };
	}
};

// Serial workspace scan: load every workspace file and diagnose it in-process.
// Returns [{ uri, diags }]. Used by the linter for --jobs=1; the parallel path
// (linter/run.uc) reuses loadWorkspaceDocs + diagnoseDoc across forked workers.
export function diagnoseWorkspace(config) {
	let results = [];
	for (let doc in loadWorkspaceDocs(config))
		push(results, diagnoseDoc(doc));
	return results;
};
