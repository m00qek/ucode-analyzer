import * as fs from 'fs';
import { scan } from 'ucode_language_server.glob';

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

let CANDIDATES = ['src', 'test', 'files/usr/share/ucode'];

function detectLibraryPaths(workspaceDir) {
	let paths = filter(CANDIDATES, (p) => hasUcFiles(workspaceDir + '/' + p));
	return length(paths) > 0 ? paths : ['src'];
}

function writeDefault(workspaceDir) {
	let lspDir = workspaceDir + '/.lsp';
	let stat = fs.stat(lspDir);
	if (!stat) fs.mkdir(lspDir);

	let paths = detectLibraryPaths(workspaceDir);
	let config = { workspace: { libraryPaths: paths } };

	let f = fs.open(lspDir + '/config.json', 'w');
	if (f) {
		f.write(sprintf('%J\n', config));
		f.close();
	}

	return config;
}

// Loads and deep-merges user config and project config.
// Project config wins on conflicts. Creates .lsp/config.json if absent.
export function load(configDir, workspaceDir) {
	let userConfig    = readJson(configDir + '/config.json') ?? {};
	let projectConfig = readJson(workspaceDir + '/.lsp/config.json');
	if (projectConfig === null)
		projectConfig = writeDefault(workspaceDir);
	return deepMerge(userConfig, projectConfig);
};
