import { describe, it, assert } from 'utest';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as platform from 'ucode_analyzer.language_server.platform';

const DECL_DIR = '/app/src/ucode_analyzer/declarations';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
	selfSrcDir: '/app/src/ucode_analyzer',
};

let V1 = '2025.07.18~3f64c808';
let V2 = '2026.01.16~85922056';

let FS_URI   = 'file://' + DECL_DIR + '/fs.d.uc';
let IO_URI   = 'file://' + DECL_DIR + '/io.d.uc';
let MATH_URI = 'file://' + DECL_DIR + '/math.d.uc';

function loadVersions(uris) {
	dag.init(_config);
	let result = {};
	for (let uri in uris) {
		dag.addFromDisk(uri);
		let v = dag.versionsOf(uri);
		if (v) result[uri] = v;
	}
	return result;
}

describe('platform — @since filtering with injected query', () => {
	it('hides @since V2 symbols when V1 is installed', () => {
		let versions = loadVersions([FS_URI]);
		platform.init(versions, (name) => (name === 'fs') ? V1 : null);

		assert.match(true,  platform.moduleAvailable(FS_URI));
		assert.match(false, platform.symbolAvailable(FS_URI, V2));
		assert.match(true,  platform.symbolAvailable(FS_URI, null));
	});

	it('shows @since V2 symbols when V2 is installed', () => {
		let versions = loadVersions([FS_URI]);
		platform.init(versions, (name) => (name === 'fs') ? V2 : null);

		assert.match(true, platform.moduleAvailable(FS_URI));
		assert.match(true, platform.symbolAvailable(FS_URI, V2));
	});

	it('hides a single-version module when not installed', () => {
		let versions = loadVersions([IO_URI]);
		platform.init(versions, (name) => null);

		assert.match(false, platform.moduleAvailable(IO_URI));
		assert.match(false, platform.symbolAvailable(IO_URI, null));
	});

	it('shows everything when installed version is not in the list', () => {
		let versions = loadVersions([MATH_URI]);
		platform.init(versions, (name) => '2099.01.01~ffffffff');

		assert.match(true, platform.moduleAvailable(MATH_URI));
		assert.match(true, platform.symbolAvailable(MATH_URI, V1));
	});

	it('modules without Versions header are always available regardless of query', () => {
		// Load a declaration file, but init with an empty map (simulating no version info).
		platform.init({}, (name) => null);
		assert.match(true, platform.moduleAvailable(FS_URI));
		assert.match(true, platform.symbolAvailable(FS_URI, V2));
	});
});

describe('platform — real package manager detection', () => {
	it('detects that ucode-mod-fs is installed in this container', () => {
		let versions = loadVersions([FS_URI]);
		platform.init(versions);  // uses real apk

		// In the test container, ucode-mod-fs is always installed.
		assert.match(true, platform.moduleAvailable(FS_URI));
	});

	it('dup2 (@since V2) is available because container runs 25.12.x', () => {
		let versions = loadVersions([FS_URI]);
		platform.init(versions);

		// The container is 25.12.x so V2 is the installed version.
		assert.match(true, platform.symbolAvailable(FS_URI, V2));
	});
});
