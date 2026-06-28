import { describe, it, assert, mock } from 'utest';
import { load } from 'language_server.config';

let CONFIG_DIR    = '/config';
let WORKSPACE_DIR = '/workspace';

// Minimum project config — enough to skip writeDefault.
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
