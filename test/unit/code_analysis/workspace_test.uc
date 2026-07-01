import { describe, it, assert } from 'utest';
import { isWorkspaceUri } from 'code_analysis.workspace';

// selfSrcDir and one systemLibPath sit UNDER the workspace so their exclusion
// (and its boundary) is actually exercised — a path outside /app is already
// excluded by the workspace-dir check alone.
let cfg = {
	workspaceDir:   '/app',
	selfSrcDir:     '/app/vendor/src',
	systemLibPaths: ['/app/syslib'],
};

function ws(path, nested) {
	return isWorkspaceUri('file://' + path, cfg, nested ?? []);
}

describe('workspace — isWorkspaceUri classification', () => {
	it('includes a file under the workspace dir', () => {
		assert.match(true, ws('/app/src/main.uc'));
	});

	it('excludes a file outside the workspace dir', () => {
		assert.match(false, ws('/other/x.uc'));
	});

	it('does not treat a sibling sharing a name prefix as inside (/app-lib vs /app)', () => {
		assert.match(false, ws('/app-lib/x.uc'));
	});

	it('excludes the server bundled sources (selfSrcDir)', () => {
		assert.match(false, ws('/app/vendor/src/util.uc'));
	});

	it('does not over-exclude a sibling of selfSrcDir (boundary)', () => {
		assert.match(true, ws('/app/vendor/src-extra/util.uc'));
	});

	it('excludes a system library path', () => {
		assert.match(false, ws('/app/syslib/fs.uc'));
	});

	it('does not over-exclude a sibling of a system library path (boundary)', () => {
		assert.match(true, ws('/app/syslibs/fs.uc'));
	});

	it('excludes a .d.uc declaration stub', () => {
		assert.match(false, ws('/app/src/fs.d.uc'));
	});

	it('excludes a file under a nested workspace root', () => {
		assert.match(false, ws('/app/nested/x.uc', ['/app/nested/']));
	});

	it('does not over-exclude a sibling of a nested workspace root (boundary)', () => {
		assert.match(true, ws('/app/nested-extra/x.uc', ['/app/nested/']));
	});
});
