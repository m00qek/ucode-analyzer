import { describe, it, assert } from 'utest';
import * as fs from 'fs';
import { isWorkspaceUri, loadWorkspaceDocs } from 'ucode_analyzer.code_analysis.workspace';

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

describe('workspace — excluded files', () => {
	let xcfg = { workspaceDir: '/app', workspace: { exclude: ['gen/**'] } };
	function wsx(path) {
		return isWorkspaceUri('file://' + path, xcfg, []);
	}

	it('excludes hidden folders and node_modules at any depth', () => {
		assert.match(false, wsx('/app/.git/x.uc'));
		assert.match(false, wsx('/app/src/.cache/x.uc'));
		assert.match(false, wsx('/app/web/node_modules/pkg/x.uc'));
		assert.match(true, wsx('/app/src/x.uc'));
	});

	it('excludes what workspace.exclude matches', () => {
		assert.match(false, wsx('/app/gen/x.uc'));
		assert.match(true, wsx('/app/generator/x.uc'));
	});
});

describe('workspace — loadWorkspaceDocs', () => {
	it('indexes the whole workspace, not only its library paths', () => {
		let dir = fs.mkdtemp('/tmp/workspace-XXXXXX');
		for (let f in ['main.uc', 'sub/deep.uc', 'gen/out.uc', '.hidden/h.uc', 'node_modules/m/n.uc']) {
			system(['mkdir', '-p', fs.dirname(dir + '/' + f)]);
			fs.writefile(dir + '/' + f, 'let x = 1;\n');
		}
		let docs = loadWorkspaceDocs({
			workspaceDir: dir,
			workspace: { libraryPaths: ['src'], exclude: ['gen/**'] },
			systemLibPaths: [],
		});
		system(['rm', '-rf', dir]);
		assert.match(['file://' + dir + '/main.uc', 'file://' + dir + '/sub/deep.uc'],
			sort(map(docs, (d) => d.uri)));
	});
});
