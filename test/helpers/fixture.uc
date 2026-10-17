// The fixture workspace: a few small modules for tests to import, resolve and
// navigate (test/fixtures/workspace), so tests never depend on the analyzer's
// own sources. Its library path is its root: `import … from 'greet'`.

import * as fs from 'fs';

export const WORKSPACE = '/app/test/fixtures/workspace';

// A DAG / server config for the fixture workspace; extra fields are merged
// into `workspace` (e.g. { globals: [...] }).
export function config(extra) {
	return {
		workspaceDir: WORKSPACE,
		selfSrcDir:   '/app/src/ucode_analyzer',
		workspace:    { libraryPaths: ['.'], ...(extra ?? {}) },
	};
};

// The file:// URI of a fixture, by path relative to the workspace.
export function uri(rel) {
	return 'file://' + WORKSPACE + '/' + rel;
};

// A fixture's text.
export function read(rel) {
	let text = fs.readfile(WORKSPACE + '/' + rel);
	if (text === null) die('no fixture ' + rel);
	return text;
};
