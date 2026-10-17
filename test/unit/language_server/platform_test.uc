import { describe, it, assert, afterEach } from 'utest';
import * as platform from 'ucode_analyzer.language_server.platform';

let URI_FS   = 'file:///app/src/ucode_analyzer/declarations/fs.d.uc';
let URI_IO   = 'file:///app/src/ucode_analyzer/declarations/io.d.uc';
let URI_MATH = 'file:///app/src/ucode_analyzer/declarations/math.d.uc';
let URI_STD  = 'file:///app/src/ucode_analyzer/declarations/global.d.uc';

let V1 = '2025.07.18~3f64c808';
let V2 = '2026.01.16~85922056';

afterEach(() => {
	// Reset to uninitialised state between tests.
	platform.init({});
});

describe('platform — uninitialised (no init call)', () => {
	it('moduleAvailable returns true for any URI when init was never called', () => {
		assert.match(true, platform.moduleAvailable(URI_FS));
		assert.match(true, platform.moduleAvailable('file:///anything.d.uc'));
	});

	it('symbolAvailable returns true for any URI/since combination', () => {
		assert.match(true, platform.symbolAvailable(URI_FS, V2));
		assert.match(true, platform.symbolAvailable(URI_FS, null));
	});
});

describe('platform.init — module availability', () => {
	it('module is available when queryFn returns the matching version', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => (name === 'fs') ? V1 : null
		);
		assert.match(true, platform.moduleAvailable(URI_FS));
	});

	it('module is unavailable when queryFn returns null (not installed)', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => null
		);
		assert.match(false, platform.moduleAvailable(URI_FS));
	});

	it('module without Versions info is always available', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => null  // fs not installed
		);
		// URI_MATH not in declVersions → no entry in index → true
		assert.match(true, platform.moduleAvailable(URI_MATH));
	});

	it('global is always at the latest version index', () => {
		platform.init(
			{ [URI_STD]: [V1, V2] },
			(name) => null
		);
		assert.match(true, platform.moduleAvailable(URI_STD));
	});
});

describe('platform.init — symbol availability', () => {
	it('symbol without @since is always available when module is installed', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => V1
		);
		assert.match(true, platform.symbolAvailable(URI_FS, null));
	});

	it('symbol without @since is unavailable when module is not installed', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => null
		);
		assert.match(false, platform.symbolAvailable(URI_FS, null));
	});

	it('@since first version is available at first version', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => V1
		);
		assert.match(true, platform.symbolAvailable(URI_FS, V1));
	});

	it('@since second version is hidden at first version', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => V1
		);
		assert.match(false, platform.symbolAvailable(URI_FS, V2));
	});

	it('@since second version is available at second version', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => V2
		);
		assert.match(true, platform.symbolAvailable(URI_FS, V2));
	});

	it('@since version not in list is treated as available', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => V1
		);
		assert.match(true, platform.symbolAvailable(URI_FS, 'unknown-version'));
	});
});

describe('platform.init — installed version not in list', () => {
	it('version newer than all listed versions shows all symbols', () => {
		platform.init(
			{ [URI_FS]: [V1, V2] },
			(name) => '2099.01.01~ffffffff'
		);
		assert.match(true, platform.moduleAvailable(URI_FS));
		assert.match(true, platform.symbolAvailable(URI_FS, V2));
	});
});

describe('platform.init — module with single version', () => {
	it('single-version module installed at that version makes all symbols available', () => {
		platform.init(
			{ [URI_IO]: [V2] },
			(name) => V2
		);
		assert.match(true, platform.moduleAvailable(URI_IO));
		assert.match(true, platform.symbolAvailable(URI_IO, V2));
	});

	it('single-version module not installed hides everything', () => {
		platform.init(
			{ [URI_IO]: [V2] },
			(name) => null
		);
		assert.match(false, platform.moduleAvailable(URI_IO));
		assert.match(false, platform.symbolAvailable(URI_IO, null));
	});
});
