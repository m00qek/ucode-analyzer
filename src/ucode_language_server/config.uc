import * as fs from 'fs';

function deepMerge(base, over) {
	if (type(over) !== 'object' || type(base) !== 'object')
		return over;

	let result = {};

	for (let k in keys(base))
		result[k] = base[k];

	for (let k in keys(over))
		result[k] = deepMerge(result[k], over[k]);

	return result;
}

function readJson(path) {
	let f = fs.open(path, 'r');
	if (!f)
		return null;

	let content = f.read('all');
	f.close();
	return json(content);
}

// Loads and deep-merges user config and project config.
// Project config wins on conflicts; arrays are replaced, not concatenated.
export function load(configDir, workspaceDir) {
	let userConfig    = readJson(configDir + '/config.json') ?? {};
	let projectConfig = readJson(workspaceDir + '/.lsp/config.json') ?? {};
	return deepMerge(userConfig, projectConfig);
};
