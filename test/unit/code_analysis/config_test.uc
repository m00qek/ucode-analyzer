import { describe, it, assert, mock } from 'utest';
import * as fs from 'fs';
import { load, init } from 'code_analysis.config';

let CONFIG_DIR    = '/config';
let WORKSPACE_DIR = '/workspace';

// Minimum project config, so library paths are not detected.
let MIN_PROJECT = '{"workspace":{"libraryPaths":["src"]}}';

describe('config.load — systemLibPaths', () => {
	it('applies default [/usr/share/ucode] when neither config sets it', () => {
		mock.global.patch('fs', { data: {
			[CONFIG_DIR    + '/config.json']:         '{}',
			[WORKSPACE_DIR + '/.lsp/config.json']:   MIN_PROJECT,
		} });
		let cfg = load(CONFIG_DIR, WORKSPACE_DIR);
		mock.global.unpatch('fs');

		assert.match(['/usr/share/ucode'], cfg.systemLibPaths);
	});

	it('respects systemLibPaths set in user config', () => {
		mock.global.patch('fs', { data: {
			[CONFIG_DIR    + '/config.json']:         '{"systemLibPaths":["/custom/ucode"]}',
			[WORKSPACE_DIR + '/.lsp/config.json']:   MIN_PROJECT,
		} });
		let cfg = load(CONFIG_DIR, WORKSPACE_DIR);
		mock.global.unpatch('fs');

		assert.match(['/custom/ucode'], cfg.systemLibPaths);
	});

	it('respects systemLibPaths set in project config', () => {
		mock.global.patch('fs', { data: {
			[CONFIG_DIR    + '/config.json']:         '{}',
			[WORKSPACE_DIR + '/.lsp/config.json']:
				'{"workspace":{"libraryPaths":["src"]},"systemLibPaths":["/project/ucode"]}',
		} });
		let cfg = load(CONFIG_DIR, WORKSPACE_DIR);
		mock.global.unpatch('fs');

		assert.match(['/project/ucode'], cfg.systemLibPaths);
	});

	it('project config wins over user config for systemLibPaths', () => {
		mock.global.patch('fs', { data: {
			[CONFIG_DIR    + '/config.json']:         '{"systemLibPaths":["/user/ucode"]}',
			[WORKSPACE_DIR + '/.lsp/config.json']:
				'{"workspace":{"libraryPaths":["src"]},"systemLibPaths":["/project/ucode"]}',
		} });
		let cfg = load(CONFIG_DIR, WORKSPACE_DIR);
		mock.global.unpatch('fs');

		assert.match(['/project/ucode'], cfg.systemLibPaths);
	});
});

// A scratch workspace holding the given files (paths relative to it).
function workspaceWith(files) {
	let dir = fs.mkdtemp('/tmp/config-XXXXXX');
	for (let f in files) {
		system(['mkdir', '-p', fs.dirname(dir + '/' + f)]);
		fs.writefile(dir + '/' + f, 'let x = 1;\n');
	}
	return dir;
}

describe('config.load — library paths', () => {
	it('detects the candidate folders that hold .uc files, writing nothing', () => {
		let dir = workspaceWith(['src/a.uc', 'test/b.uc', 'docs/c.uc']);
		let cfg = load(dir, dir);
		let lspDir = fs.stat(dir + '/.lsp');
		system(['rm', '-rf', dir]);
		assert.match(['src', 'test'], cfg.workspace.libraryPaths);
		assert.match(null, lspDir);
	});

	it('falls back to the workspace root', () => {
		let dir = workspaceWith(['a.uc']);
		let cfg = load(dir, dir);
		system(['rm', '-rf', dir]);
		assert.match(['.'], cfg.workspace.libraryPaths);
	});

	it('uses the library paths of the project config', () => {
		let dir = workspaceWith(['src/a.uc']);
		fs.mkdir(dir + '/.lsp');
		fs.writefile(dir + '/.lsp/config.json', '{"workspace":{"libraryPaths":["lib"],"exclude":["gen/**"]}}');
		let cfg = load(dir, dir);
		system(['rm', '-rf', dir]);
		assert.match(['lib'], cfg.workspace.libraryPaths);
		assert.match(['gen/**'], cfg.workspace.exclude);
	});
});

describe('config.init', () => {
	it('writes the detected library paths once', () => {
		let dir = workspaceWith(['src/a.uc']);
		let first = init(dir);
		let written = json(fs.readfile(dir + '/.lsp/config.json'));
		fs.writefile(dir + '/.lsp/config.json', '{"workspace":{"libraryPaths":["mine"]}}');
		let second = init(dir);
		let kept = json(fs.readfile(dir + '/.lsp/config.json'));
		system(['rm', '-rf', dir]);
		assert.match({ path: dir + '/.lsp/config.json', created: true }, first);
		assert.match({ workspace: { libraryPaths: ['src'] } }, written);
		assert.match(false, second.created);
		assert.match(['mine'], kept.workspace.libraryPaths);
	});
});
