import { describe, it, assert } from 'utest';
import * as native from 'rpc_client.native';

const WS = '/app/test/fixtures/linter';

// Spawn the linter binary, drain stdout to EOF, return { out, code }. Diagnostics
// go to stdout; the human summary goes to stderr (not captured here).
function runLinter(extra) {
	let args = [ '-L', '/app/src', '/app/src/ucode-linter.uc' ];
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

describe('ucode-linter — workspace mode', () => {
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

describe('ucode-linter — file mode', () => {
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
