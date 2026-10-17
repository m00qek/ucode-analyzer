import { describe, it, assert, afterEach } from 'utest';
import * as fs from 'fs';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { isWorkspaceUri, loadWorkspace, loadWorkspaceDocs, workspaceUris,
         diagnoseFile, diagnoseDoc, diagnoseWorkspace } from 'ucode_analyzer.code_analysis.workspace';

let _dirs = [];

// A temporary directory holding `files` ({ relative path: text }).
function tree(files) {
	let dir = fs.mkdtemp('/tmp/workspace-XXXXXX');
	push(_dirs, dir);
	for (let f, text in files) {
		system(['mkdir', '-p', fs.dirname(dir + '/' + f)]);
		fs.writefile(dir + '/' + f, text);
	}
	return dir;
}

// The DAG outlives a test: drop what this one indexed.
afterEach(() => {
	for (let dir in _dirs) {
		for (let uri in dag.allUris())
			if (index(uri, 'file://' + dir + '/') === 0) dag.remove(uri);
		system(['rm', '-rf', dir]);
	}
	_dirs = [];
});

// The paths of file:// URIs, relative to dir, sorted.
function rel(dir, uris) {
	return sort(map(uris, (u) => replace(u, 'file://' + dir + '/', '')));
}

// The DAG's files under this test's directories, sorted.
function indexed() {
	return sort(filter(dag.allUris(), (u) => length(filter(_dirs, (d) => index(u, 'file://' + d + '/') === 0))));
}

// selfSrcDir and one systemLibPath sit UNDER the workspace so their handling
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

	it('includes the server sources of a checkout in the workspace', () => {
		assert.match(true, ws('/app/vendor/src/util.uc'));
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
		let files = {};
		for (let f in ['main.uc', 'sub/deep.uc', 'gen/out.uc', '.hidden/h.uc', 'node_modules/m/n.uc'])
			files[f] = 'let x = 1;\n';
		let dir = tree(files);
		let docs = loadWorkspaceDocs({
			workspaceDir: dir,
			workspace: { libraryPaths: ['src'], exclude: ['gen/**'] },
			systemLibPaths: [],
		});
		assert.match(['main.uc', 'sub/deep.uc'], rel(dir, map(docs, (d) => d.uri)));
	});

	it('returns parsed documents without scope maps', () => {
		let dir = tree({ 'main.uc': 'let x = 1;\n' });
		let docs = loadWorkspaceDocs({ workspaceDir: dir, systemLibPaths: [] });
		assert.match(1, length(docs));
		assert.match('let x = 1;\n', docs[0].text);
		assert.match('resource', type(docs[0].tree));
		assert.match(null, docs[0].scopeMap);
	});

	it('indexes a nested workspace and a library outside the workspace, but returns neither', () => {
		let lib = tree({ 'shared.uc': 'export function share() {};\n' });
		let dir = tree({
			'main.uc': "import { share } from 'shared';\nshare();\n",
			'nested/.lsp/config.json': '{}',
			'nested/inner.uc': 'let y = 2;\n',
		});
		let docs = loadWorkspaceDocs({ workspaceDir: dir, workspace: { libraryPaths: [lib] }, systemLibPaths: [] });
		assert.match(['main.uc'], rel(dir, map(docs, (d) => d.uri)));
		assert.match(sort(['file://' + lib + '/shared.uc', 'file://' + dir + '/main.uc', 'file://' + dir + '/nested/inner.uc']),
			indexed());
		// The library resolves for the workspace's imports.
		assert.match('file://' + lib + '/shared.uc', dag.importsOf('file://' + dir + '/main.uc')[0].resolvedUri);
	});
});

describe('workspace — loadWorkspace', () => {
	it('indexes workspace files, outside libraries, declarations and system libraries', () => {
		let lib = tree({ 'shared.uc': 'export let s = 1;\n' });
		let sys = tree({ 'syslib.uc': 'export let t = 1;\n' });
		let pkg = tree({
			'declarations/global.d.uc': '// Versions: 24.10, 25.12\nexport function hello() {};\n',
			'declarations/extra.d.uc': 'export let e = 1;\n',
		});
		let dir = tree({ 'main.uc': 'let x = 1;\n', '.git/hook.uc': 'let h = 1;\n' });
		let versions = loadWorkspace({
			workspaceDir: dir, selfSrcDir: pkg, systemLibPaths: [sys],
			workspace: { libraryPaths: ['.', lib] },
		});
		assert.match(sort([
			'file://' + dir + '/main.uc', 'file://' + lib + '/shared.uc', 'file://' + sys + '/syslib.uc',
			'file://' + pkg + '/declarations/global.d.uc', 'file://' + pkg + '/declarations/extra.d.uc',
		]), indexed());
		// The @version map: declarations with a Versions header only.
		assert.match({ ['file://' + pkg + '/declarations/global.d.uc']: ['24.10', '25.12'] }, versions);
	});
});

describe('workspace — workspaceUris', () => {
	it('lists the DAG files that belong to the workspace', () => {
		let lib = tree({ 'shared.uc': 'export let s = 1;\n' });
		let pkg = tree({ 'declarations/global.d.uc': 'export function hello() {};\n' });
		let dir = tree({
			'main.uc': 'let x = 1;\n',
			'src/util.uc': 'let y = 1;\n',
			'nested/.lsp/config.json': '{}',
			'nested/inner.uc': 'let z = 1;\n',
			'types.d.uc': 'export let d = 1;\n',
		});
		let config = { workspaceDir: dir, selfSrcDir: pkg, systemLibPaths: [], workspace: { libraryPaths: ['.', lib] } };
		loadWorkspace(config);
		assert.match(['main.uc', 'src/util.uc'], rel(dir, workspaceUris(config)));
	});
});

describe('workspace — diagnosing', () => {
	let UNUSED = "let unused = 1;\n";

	function codes(diags) {
		return map(diags, (d) => d.code);
	}

	it('diagnoseFile reads a file that is not open from disk', () => {
		let dir = tree({ 'a.uc': UNUSED });
		loadWorkspace({ workspaceDir: dir, systemLibPaths: [] });
		assert.match(['unused-var'], codes(diagnoseFile('file://' + dir + '/a.uc')));
	});

	it('diagnoseFile diagnoses the open text of an open file', () => {
		let dir = tree({ 'a.uc': UNUSED });
		let uri = 'file://' + dir + '/a.uc';
		loadWorkspace({ workspaceDir: dir, systemLibPaths: [] });
		documents.open(uri, 'export let used = 1;\n', 1);
		let diags = diagnoseFile(uri);
		documents.close(uri);
		assert.match([], diags);
	});

	it('diagnoseFile gives nothing for a file that cannot be read', () => {
		let dir = tree({});
		loadWorkspace({ workspaceDir: dir, systemLibPaths: [] });
		assert.match([], diagnoseFile('file://' + dir + '/missing.uc'));
	});

	it('diagnoseDoc attaches the scope map and diagnoses', () => {
		let dir = tree({ 'a.uc': UNUSED });
		let docs = loadWorkspaceDocs({ workspaceDir: dir, systemLibPaths: [] });
		let r = diagnoseDoc(docs[0]);
		assert.match('file://' + dir + '/a.uc', r.uri);
		assert.match(['unused-var'], codes(r.diags));
		assert.match('array', type(docs[0].scopeMap));
	});

	it('diagnoseDoc isolates a failure to its file', () => {
		let r = diagnoseDoc({ uri: 'file:///broken.uc', text: 'let x;', tree: null });
		assert.match({ uri: 'file:///broken.uc', diags: [] }, r);
	});

	it('diagnoseWorkspace diagnoses every workspace file', () => {
		let dir = tree({ 'a.uc': UNUSED, 'b.uc': 'print(1);\n', 'gen/c.uc': UNUSED });
		let results = diagnoseWorkspace({ workspaceDir: dir, systemLibPaths: [], workspace: { exclude: ['gen/**'] } });
		let byFile = {};
		for (let r in results) byFile[rel(dir, [r.uri])[0]] = codes(r.diags);
		assert.match({ 'a.uc': ['unused-var'], 'b.uc': [] }, byFile);
	});
});
