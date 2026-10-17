import * as fs from 'fs';
import { scan } from 'ucode_analyzer.code_analysis.glob';

function readJson(path) {
	let f = fs.open(path, 'r');
	if (!f) return null;
	let content = f.read('all');
	f.close();
	return json(content);
}

function deepMerge(base, over) {
	if (type(over) !== 'object' || type(base) !== 'object')
		return over;

	let result = {};
	for (let k in keys(base))  result[k] = base[k];
	for (let k in keys(over))  result[k] = deepMerge(result[k], over[k]);
	return result;
}

function hasUcFiles(absPath) {
	return length(scan(absPath, ['**/*.uc'], [])) > 0;
}

// Folders that commonly hold a project's importable modules.
let CANDIDATES = ['src', 'test', 'files/usr/share/ucode'];

// The library paths of a workspace with no configured ones: the candidate
// folders that hold .uc files, else the workspace root.
export function detectLibraryPaths(workspaceDir) {
	let paths = filter(CANDIDATES, (p) => hasUcFiles(workspaceDir + '/' + p));
	return length(paths) > 0 ? paths : ['.'];
};

// The configured library paths as absolute directories: relative ones are
// under the workspace, and `.` is the workspace itself.
export function libraryDirs(config) {
	let workdir = config.workspaceDir ?? '/';
	return map(config.workspace?.libraryPaths ?? ['src'], (p) =>
		(substr(p, 0, 1) === '/') ? p : (p === '.') ? workdir : workdir + '/' + p);
};

function projectConfigPath(workspaceDir) {
	return workspaceDir + '/.lsp/config.json';
}

// Loads and deep-merges user config and project config; project config wins
// on conflicts. Library paths not set by either are detected afresh on every
// load, so they follow the workspace's layout; nothing is written.
export function load(configDir, workspaceDir) {
	let userConfig    = readJson(configDir + '/config.json') ?? {};
	let projectConfig = readJson(projectConfigPath(workspaceDir)) ?? {};
	let merged = deepMerge(userConfig, projectConfig);
	merged.workspace ??= {};
	if (!merged.workspace.libraryPaths)
		merged.workspace.libraryPaths = detectLibraryPaths(workspaceDir);
	if (!merged.systemLibPaths)
		merged.systemLibPaths = ['/usr/share/ucode'];
	return merged;
};

// Write a project config holding the detected library paths, unless the
// workspace already has one. Returns { path, created }.
export function init(workspaceDir) {
	let path = projectConfigPath(workspaceDir);
	if (fs.stat(path))
		return { path, created: false };

	let lspDir = workspaceDir + '/.lsp';
	if (!fs.stat(lspDir) && !fs.mkdir(lspDir))
		die(sprintf('cannot create %s: %s', lspDir, fs.error()));

	let config = { workspace: { libraryPaths: detectLibraryPaths(workspaceDir) } };
	if (fs.writefile(path, sprintf('%.2J\n', config)) === null)
		die(sprintf('cannot write %s: %s', path, fs.error()));
	return { path, created: true };
};
