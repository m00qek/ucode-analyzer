import { describe, it, assert, setup, teardown, contains } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

// Open a document and pull its diagnostics, returning the diagnostic array.
let diagnose = function(uri, text) {
	lsp.open(proc, uri, text);
	return lsp.documentDiagnostics(proc, uri).items;
};

describe('textDocument/diagnostic', () => {

	it('reports an error diagnostic for unresolvable import', () => {
		let diags = diagnose('file:///t.uc', "import { foo } from 'no_such_module';");
		// Expect at least one ERROR-severity diagnostic for the bad import.
		// (An unused-import HINT for 'foo' may also be present.)
		let errDiags = filter(diags, (d) => d.severity === 1);
		assert.match(true, length(errDiags) >= 1);
	});

	it('reports empty diagnostics for a valid file', () => {
		// All declarations are used, no syntax errors, no bad imports.
		let diags = diagnose('file:///t.uc', "let x = 1;\nx;\n");
		assert.match(0, length(diags));
	});

	it('warns for an undefined identifier reference', () => {
		let diags = diagnose('file:///t.uc', "let x = ghost;\n");
		// Should include at least a warning for 'ghost' (undefined) and one for 'x' (unused)
		let ghostDiag = null;
		for (let d in diags) if (index(d.message, 'ghost') >= 0) { ghostDiag = d; break; }
		if (ghostDiag === null) die('expected a diagnostic mentioning ghost');
		assert.match(2, ghostDiag.severity);  // WARNING
	});

	it('warns for an unused variable with severity WARNING (2)', () => {
		let diags = diagnose('file:///t.uc', "let neverUsed = 42;\n");
		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);  // WARNING
		assert.match(contains('neverUsed'), diags[0].message);
	});

	it('reports error when a named import does not exist in the module', () => {
		let diags = diagnose('file:///t.uc', "import { noSuchExport } from 'parser';\n");
		// Expect at least one ERROR about the missing export.
		let errDiags = filter(diags, (d) =>
			d.severity === 1 && index(d.message, 'noSuchExport') >= 0);
		assert.match(true, length(errDiags) >= 1);
	});

	it('hints for == with severity 4 (Hint)', () => {
		let diags = diagnose('file:///t.uc', "let x = 1;\nlet y = x == 1;\ny;\n");
		let eqDiag = null;
		for (let d in diags) if (index(d.message, '===') >= 0) { eqDiag = d; break; }
		if (eqDiag === null) die('expected a === hint diagnostic');
		assert.match(4, eqDiag.severity);
	});

	it('reports syntax error for malformed code', () => {
		let diags = diagnose('file:///t.uc', "let x = ;\n");
		assert.match(true, length(diags) > 0);
		assert.match(1, diags[0].severity);
	});

	// tree-sitter parses this small file as one ERROR; the server re-parses it
	// with the closers appended and reports them, not the whole file, as missing.
	it('reports each block left open at the end of a small file as a missing }', () => {
		let src = cursors("function f(a) {\n\tif (a) {\n\t\tf(a);\n$0");
		let diags = diagnose('file:///t.uc', src.text);
		let eof = src.at[0];
		assert.match([
			{ message: "Syntax error: missing '}'", range: { start: eof, end: eof } },
			{ message: "Syntax error: missing '}'", range: { start: eof, end: eof } },
		], map(filter(diags, (d) => d.code === 'syntax-error'),
			(d) => ({ message: d.message, range: d.range })));
	});

	it('reports not-a-function for @param {string} annotated param when called', () => {
		let diags = diagnose('file:///t.uc',
			"/**\n * @param {string} name\n */\nfunction greet(name) { name(); }\ngreet('x');\n");
		let d = filter(diags, (d) => index(d.message, 'not a function') >= 0);
		assert.match(true, length(d) >= 1);
		assert.match(1, d[0].severity);
	});

	it('reports error when calling a string variable', () => {
		let diags = diagnose('file:///t.uc', "let x = 'hello';\nx();\nx;\n");
		let d = filter(diags, (d) => index(d.message, 'not a function') >= 0);
		assert.match(true, length(d) >= 1);
		assert.match(1, d[0].severity);
	});

	it('reports error for member access on a provably-null variable', () => {
		let diags = diagnose('file:///t.uc', "let x = null;\nlet y = x.foo;\ny;\n");
		let d = filter(diags, (d) => d.code === 'null-access');
		assert.match(true, length(d) >= 1);
		assert.match(1, d[0].severity);   // ERROR
		assert.match(contains('is null'), d[0].message);
	});

	it('suppresses null member access warning inside if (x) { } guard body', () => {
		let diags = diagnose('file:///t.uc', "let x = null;\nif (x) {\n  let y = x.foo;\n  y;\n}\n");
		let nullDiags = filter(diags, (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(nullDiags));
	});

	it('suppresses null warning after if (!x) return guard clause', () => {
		let diags = diagnose('file:///t.uc', "let x = null;\nif (!x) return;\nlet y = x.foo;\ny;\n");
		let nullDiags = filter(diags, (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(nullDiags));
	});

	it('reports deprecated hint for use of @deprecated imported symbol', () => {
		let diags = diagnose('file:///t.uc', "import { oldFn } from 'deprecated';\noldFn();\n");
		let depDiags = filter(diags, (d) => d.message === 'Deprecated');
		assert.match(true, length(depDiags) >= 1);
		assert.match(4, depDiags[0].severity);  // HINT
		assert.match(contains([2]), depDiags[0].tags);  // TAG_DEPRECATED
	});

	it('does not report deprecated hint for non-deprecated imported symbol', () => {
		let diags = diagnose('file:///t.uc', "import { newFn } from 'deprecated';\nnewFn();\n");
		let depDiags = filter(diags, (d) => d.message === 'Deprecated');
		assert.match(0, length(depDiags));
	});

	it('reports unused-import hint for an import that is never used', () => {
		let diags = diagnose('file:///t.uc', "import * as p from 'parser';\n");
		let d = filter(diags, (d) => d.code === 'unused-import');
		assert.match(1, length(d));
		assert.match(4, d[0].severity);   // HINT
		assert.match(contains("'p'"), d[0].message);
	});

	it('does not report unused-import for an import that is used', () => {
		let diags = diagnose('file:///t.uc', "import * as p from 'parser';\np.parse;\n");
		let d = filter(diags, (d) => d.code === 'unused-import');
		assert.match(0, length(d));
	});

	it('reports redeclared-var error for duplicate let in same block', () => {
		let diags = diagnose('file:///t.uc', "let x = 1;\nlet x = 2;\n");
		let d = filter(diags, (d) => d.code === 'redeclared-var');
		assert.match(1, length(d));
		assert.match(1, d[0].severity);   // ERROR
		assert.match(contains("'x'"), d[0].message);
	});

	it('reports duplicate-key warning for duplicate object keys', () => {
		let diags = diagnose('file:///t.uc', "let o = { a: 1, a: 2 };\no;\n");
		let d = filter(diags, (d) => d.code === 'duplicate-key');
		assert.match(1, length(d));
		assert.match(2, d[0].severity);   // WARNING
		assert.match(contains("'a'"), d[0].message);
	});

	it('reports const-assignment error for reassigning a const variable', () => {
		let diags = diagnose('file:///t.uc', "const x = 1;\nx = 2;\n");
		let d = filter(diags, (d) => d.code === 'const-assignment');
		assert.match(1, length(d));
		assert.match(1, d[0].severity);   // ERROR
		assert.match(contains("'x'"), d[0].message);
	});

	it('reports missing-return warning for @returns function missing a path', () => {
		let diags = diagnose('file:///t.uc', "/**\n * @returns {int}\n */\nfunction f() {\n  let x = 1;\n}\n");
		let d = filter(diags, (d) => d.code === 'missing-return');
		assert.match(1, length(d));
		assert.match(2, d[0].severity);   // WARNING
	});

	it('reports for-in-non-iterable warning for iterating over an integer', () => {
		let diags = diagnose('file:///t.uc', "for (let x in 42) { x; }\n");
		let d = filter(diags, (d) => d.code === 'for-in-non-iterable');
		assert.match(1, length(d));
		assert.match(2, d[0].severity);   // WARNING
	});

	it('no for-in-non-iterable warning when iterating over an array', () => {
		let diags = diagnose('file:///t.uc', "let arr = [1,2,3];\nfor (let x in arr) { x; }\n");
		let d = filter(diags, (d) => d.code === 'for-in-non-iterable');
		assert.match(0, length(d));
	});

	it('does not warn for m.prop when m is guarded by ternary condition', () => {
		let diags = diagnose('file:///ternary_narrow.uc',
			"/**\n * @param {object|null} m\n */\nfunction f(m) { let x = m ? m.create : null; x; }\nf(null);\n");
		let typeErrs = filter(diags, (d) => d.code === 'may-be-null' || d.code === 'unknown-property');
		assert.match(0, length(typeErrs));
	});

	it('does not warn unknown-property when assigning a new key to a dict', () => {
		// ucode dicts are open: `obj.newKey = ...` legitimately adds a property.
		let diags = diagnose('file:///assign_new_key.uc',
			"let obj = { a: 1 };\nobj.b = 2;\nobj;\n");
		let errs = filter(diags, (d) => d.code === 'unknown-property');
		assert.match(0, length(errs));
	});

	it('still warns unknown-property when reading a missing key', () => {
		let diags = diagnose('file:///read_missing_key.uc',
			"let obj = { a: 1 };\nlet x = obj.b;\nx;\n");
		let errs = filter(diags, (d) => d.code === 'unknown-property');
		assert.match(1, length(errs));
	});

	it('narrows to non-null in the true branch of type(x) === "object"', () => {
		// object/array have no singleton type, but type(x)==='object' still proves
		// x is non-null (type(null) is 'null').
		let diags = diagnose('file:///type_obj.uc',
			"function f() { let r = null; if (type(r) === 'object') { return r.x; } return 0; }\nf();\n");
		let errs = filter(diags, (d) => d.code === 'may-be-null');
		assert.match(0, length(errs));
	});

	it('narrows after a die() guard clause (die never returns)', () => {
		let diags = diagnose('file:///die_guard.uc',
			"function f() { let r = null; if (r === null) die('x'); return r.k; }\nf();\n");
		let errs = filter(diags, (d) => d.code === 'may-be-null');
		assert.match(0, length(errs));
	});

	it('narrows inside a brace-less if body', () => {
		let diags = diagnose('file:///braceless_if.uc',
			"function f() { let r = null; if (r !== null) return r.x; return 0; }\nf();\n");
		let errs = filter(diags, (d) => d.code === 'may-be-null');
		assert.match(0, length(errs));
	});

	it('does not warn for m.prop on the RHS of (m === null || m.prop)', () => {
		// RHS of || is only reached when m === null is false, so m is non-null there.
		let diags = diagnose('file:///or_narrow.uc',
			"/**\n * @param {object|null} m\n */\nfunction f(m) { return m === null || m.api; }\nf(null);\n");
		let typeErrs = filter(diags, (d) => d.code === 'may-be-null' || d.code === 'unknown-property');
		assert.match(0, length(typeErrs));
	});

	it('does not warn for m.prop inside if (m && ...) body', () => {
		let diags = diagnose('file:///if_narrow.uc',
			"/**\n * @param {object|null} m\n */\nfunction f(m) { if (m && type(m.api) === 'array') { let x = m.api; x; } }\nf(null);\n");
		let typeErrs = filter(diags, (d) => d.code === 'may-be-null' || d.code === 'unknown-property');
		assert.match(0, length(typeErrs));
	});

	it('re-pulls reflect edits made by didChange', () => {
		diagnose('file:///t.uc', "let x = 1;\nx;\n");  // open clean, pull once

		lsp.change(proc, 'file:///t.uc', "import { foo } from 'bad_module';", 2);

		let diags = lsp.documentDiagnostics(proc, 'file:///t.uc').items;
		// Expect at least one diagnostic (bad import error; unused-import hint may also appear).
		assert.match(true, length(diags) >= 1);
	});

	it('returns unchanged when the previous resultId is still current', () => {
		lsp.open(proc, 'file:///t.uc', "let neverUsed = 42;\n");

		let first = lsp.documentDiagnostics(proc, 'file:///t.uc');
		assert.match('full', first.kind);

		// No edit in between -> a re-pull carrying the same resultId is 'unchanged'.
		let second = lsp.documentDiagnostics(proc, 'file:///t.uc', first.resultId);
		assert.match('unchanged', second.kind);
	});
});
