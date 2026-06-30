// Output formatting and exit-code policy for ucode-linter. Pure functions over
// the shared [{ uri, diags }] result shape — no analysis or IO — so they can be
// unit-tested in isolation and can never drift from what the editor reports.

const SEVERITY_NAME = { "1": 'error', "2": 'warning', "3": 'info', "4": 'hint' };
const SEVERITY_NUM  = { error: 1, warning: 2, info: 3, hint: 4 };

function severityName(sev) {
	return SEVERITY_NAME[sev] ?? 'error';
}

// Drop "file://" and make the path relative to root when it lives underneath it.
function relativePath(uri, root) {
	let path = (substr(uri, 0, 7) === 'file://') ? substr(uri, 7) : uri;
	if (root && length(root) > 0) {
		let prefix = (substr(root, length(root) - 1) === '/') ? root : root + '/';
		if (substr(path, 0, length(prefix)) === prefix)
			return substr(path, length(prefix));
	}
	return path;
}

// One line per diagnostic:
//   path:LINE:COL: [severity] message (code)
// with 1-based line/col (LSP ranges are 0-based). This is the format the
// nvim-lint parser expects. Returns the empty string when there are no
// diagnostics.
export function formatText(results, root) {
	let lines = [];
	for (let r in results) {
		let rel = relativePath(r.uri, root);
		for (let d in r.diags) {
			push(lines, sprintf('%s:%d:%d: [%s] %s (%s)',
				rel,
				d.range.start.line + 1,
				d.range.start.character + 1,
				severityName(d.severity ?? 1),
				d.message,
				d.code ?? ''));
		}
	}
	return join('\n', lines);
};

// Machine-readable: [{ uri, diagnostics: [<LSP Diagnostic>] }].
export function formatJson(results) {
	let out = [];
	for (let r in results)
		push(out, { uri: r.uri, diagnostics: r.diags });
	return sprintf('%J', out);
};

// Human-facing one-line tally, written to stderr by the caller.
export function summary(results) {
	let counts = [ 0, 0, 0, 0, 0 ];  // index by severity 1..4
	let filesWithProblems = 0;
	for (let r in results) {
		if (length(r.diags) > 0) filesWithProblems++;
		for (let d in r.diags)
			counts[d.severity ?? 1]++;
	}
	if (counts[1] + counts[2] + counts[3] + counts[4] === 0)
		return 'No problems found.';
	return sprintf('%d error(s), %d warning(s), %d info, %d hint(s) in %d file(s).',
		counts[1], counts[2], counts[3], counts[4], filesWithProblems);
};

// Process exit status. 0 = nothing at or above the fail-on threshold; 1 = at
// least one diagnostic at or above it. failOn 'none' never fails. Severity is
// ranked by number (1=error is most severe), so "at or above error" means
// severity <= 1.
export function exitCode(results, failOn) {
	if (failOn === 'none') return 0;
	let threshold = SEVERITY_NUM[failOn] ?? 1;  // default: error
	for (let r in results)
		for (let d in r.diags)
			if ((d.severity ?? 1) <= threshold)
				return 1;
	return 0;
};
