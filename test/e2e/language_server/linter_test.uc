import { describe, it, assert } from 'utest';
import * as native from 'rpc_client.native';
import * as fs from 'fs';

const WS = '/app/test/fixtures/linter';

// Spawn the linter binary, drain stdout to EOF, return { out, code }. Diagnostics
// go to stdout; the human summary goes to stderr (not captured here).
function runLinter(extra) {
	let args = [ '-L', '/app/src', '/app/src/ucode-analyzer.uc', 'lint' ];
	for (let a in extra) push(args, a);
	let proc = native.spawn('ucode', args);
	if (proc === null) die('failed to spawn ucode');
	let out = '';
	while (true) {
		let chunk = proc.read_raw(4096);
		if (length(chunk) === 0) break;
		out += chunk;
	}
	return { out, code: proc.close() };
}

describe('ucode-analyzer lint — workspace mode', () => {
	it('reports errors and warnings and exits 1 on errors', () => {
		let r = runLinter([ '--workspace', WS ]);
		assert.match(1, r.code);
		assert.match(true, index(r.out, 'src/errs.uc') >= 0);
		assert.match(true, index(r.out, '[error]') >= 0);
		assert.match(true, index(r.out, '(redeclared-var)') >= 0);
		assert.match(true, index(r.out, 'src/warns.uc') >= 0);
		assert.match(true, index(r.out, '[warning]') >= 0);
		assert.match(true, index(r.out, '(duplicate-key)') >= 0);
		// clean.uc has no diagnostics, so it never appears.
		assert.match(true, index(r.out, 'clean.uc') < 0);
	});

	it('emits 1-based line:col positions', () => {
		let r = runLinter([ '--workspace', WS ]);
		// redeclared `let x` is on the second line, column 5 (1-based).
		assert.match(true, index(r.out, 'src/errs.uc:2:5: [error]') >= 0);
	});

	it('exits 0 with --fail-on none despite findings', () => {
		let r = runLinter([ '--workspace', WS, '--fail-on', 'none' ]);
		assert.match(0, r.code);
		assert.match(true, index(r.out, '[error]') >= 0);  // still reported
	});

	it('emits a JSON array with --format json', () => {
		let r = runLinter([ '--workspace', WS, '--format', 'json' ]);
		let parsed = json(r.out);
		assert.match(true, type(parsed) === 'array');
		// At least one entry carries a diagnostic with a code.
		let withDiags = filter(parsed, (e) => length(e.diagnostics) > 0);
		assert.match(true, length(withDiags) >= 2);
	});

	it('exits 2 when the workspace path does not exist', () => {
		let r = runLinter([ '--workspace', '/app/test/fixtures/does-not-exist' ]);
		assert.match(2, r.code);
	});

	it('excludes a nested workspace (sub-dir with its own .lsp/config.json)', () => {
		// src/sub carries its own .lsp/config.json, making it a separate workspace.
		// Its files (buggy.uc, a redeclared-var error) must not surface in the
		// parent scan, even though buggy.uc lives under the scanned src/ tree.
		let r = runLinter([ '--workspace', WS ]);
		assert.match(true, index(r.out, 'buggy.uc') < 0);
	});

	it('serial and parallel modes produce identical output', () => {
		let serial   = runLinter([ '--jobs', '1', '--workspace', WS ]);
		let parallel = runLinter([ '--jobs', '4', '--workspace', WS ]);
		assert.match(serial.code, parallel.code);
		assert.match(serial.out, parallel.out);  // sorted, so byte-identical
	});
});

describe('ucode-analyzer lint — file mode', () => {
	it('lints a single file passed positionally', () => {
		let r = runLinter([ WS + '/src/warns.uc' ]);
		assert.match(true, index(r.out, 'warns.uc') >= 0);
		assert.match(true, index(r.out, '[warning]') >= 0);
		// A warning is below the default error threshold, so the run passes.
		assert.match(0, r.code);
	});

	it('honours --fail-on warning', () => {
		let r = runLinter([ '--fail-on', 'warning', WS + '/src/warns.uc' ]);
		assert.match(1, r.code);
	});

	it('produces no output and exits 0 for a clean file', () => {
		let r = runLinter([ WS + '/src/clean.uc' ]);
		assert.match(true, index(r.out, '[') < 0);
		assert.match(0, r.code);
	});
});

describe('ucode-analyzer lint — workspace layout', () => {
	it('lints files outside the library paths', () => {
		let dir = fs.mkdtemp('/tmp/linter-flat-XXXXXX');
		fs.mkdir(dir + '/sub');
		fs.writefile(dir + '/main.uc', 'ghost();\n');
		fs.writefile(dir + '/sub/deep.uc', 'phantom();\n');
		let r = runLinter([ '--workspace', dir ]);
		let created = fs.stat(dir + '/.lsp');
		system(['rm', '-rf', dir]);
		assert.match(true, index(r.out, "main.uc:1:1: [warning] 'ghost' is not defined") >= 0);
		assert.match(true, index(r.out, "sub/deep.uc:1:1: [warning] 'phantom' is not defined") >= 0);
		assert.match(null, created);
	});

	it('--init writes the detected config once', () => {
		let dir = fs.mkdtemp('/tmp/linter-init-XXXXXX');
		fs.mkdir(dir + '/src');
		fs.writefile(dir + '/src/a.uc', 'let a = 1;\n');
		let first = runLinter([ '--init', '--workspace', dir ]);
		let written = json(fs.readfile(dir + '/.lsp/config.json'));
		let second = runLinter([ '--init', '--workspace', dir ]);
		system(['rm', '-rf', dir]);
		assert.match(0, first.code);
		assert.match(sprintf('Wrote %s/.lsp/config.json\n', dir), first.out);
		assert.match({ workspace: { libraryPaths: ['src'] } }, written);
		assert.match(sprintf('%s/.lsp/config.json already exists; left unchanged\n', dir), second.out);
	});
});
