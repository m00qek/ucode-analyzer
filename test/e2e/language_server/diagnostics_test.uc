import { describe, it, assert, setup, teardown, any_order } from 'utest';
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

// The diagnostic the server reports from marker $from to marker $to of src.
function diagnostic(src, from, to, severity, code, message) {
	return {
		range: { start: src.at[from], end: src.at[to] },
		severity, source: 'ucode-analyzer', code, message,
	};
}

describe('textDocument/diagnostic', () => {

	it('reports an error diagnostic for unresolvable import', () => {
		let src = cursors("import { $3foo$4 } from $1'no_such_module'$2;");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match(any_order([
			diagnostic(src, 1, 2, 1, 'unknown-import', "Cannot find module 'no_such_module'"),
			diagnostic(src, 3, 4, 4, 'unused-import', "'foo' is imported but never used"),
		]), diags);
	});

	it('reports empty diagnostics for a valid file', () => {
		// All declarations are used, no syntax errors, no bad imports.
		let diags = diagnose('file:///t.uc', "let x = 1;\nx;\n");
		assert.match(0, length(diags));
	});

	it('warns for an undefined identifier reference', () => {
		let src = cursors("let $3x$4 = $1ghost$2;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match(any_order([
			diagnostic(src, 1, 2, 2, 'undefined-var', "'ghost' is not defined"),
			diagnostic(src, 3, 4, 2, 'unused-var', "'x' is declared but never used"),
		]), diags);
	});

	it('warns for an unused variable with severity WARNING (2)', () => {
		let src = cursors("let $1neverUsed$2 = 42;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 2, 'unused-var', "'neverUsed' is declared but never used"),
		], diags);
	});

	it('reports error when a named import does not exist in the module', () => {
		let src = cursors("import { $1noSuchExport$2 } from 'parser';\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match(any_order([
			diagnostic(src, 1, 2, 1, 'unknown-import-symbol', "Module has no export named 'noSuchExport'"),
			diagnostic(src, 1, 2, 4, 'unused-import', "'noSuchExport' is imported but never used"),
		]), diags);
	});

	it('hints for == with severity 4 (Hint)', () => {
		let src = cursors("let x = 1;\nlet y = x $1==$2 1;\ny;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 4, 'prefer-strict-equality', "Prefer '===' over '=='"),
		], diags);
	});

	it('reports syntax error for malformed code', () => {
		let src = cursors("let $3x$4 $1=$2 ;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match(any_order([
			diagnostic(src, 1, 2, 1, 'syntax-error', 'Syntax error'),
			diagnostic(src, 3, 4, 2, 'unused-var', "'x' is declared but never used"),
		]), diags);
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
		let src = cursors("/**\n * @param {string} name\n */\nfunction greet(name) { $1name$2(); }\ngreet('x');\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 1, 'not-a-function', "'name' is not a function (type: primitive)"),
		], diags);
	});

	it('reports error when calling a string variable', () => {
		let src = cursors("let x = 'hello';\n$1x$2();\nx;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 1, 'not-a-function', "'x' is not a function (type: primitive)"),
		], diags);
	});

	it('reports error for member access on a provably-null variable', () => {
		let src = cursors("let x = null;\nlet y = $1x$2.foo;\ny;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 1, 'null-access', "'x' is null"),
		], diags);
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
		let src = cursors("import { oldFn } from 'deprecated';\n$1oldFn$2();\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			{ ...diagnostic(src, 1, 2, 4, 'deprecated', 'Deprecated'), tags: [ 2 ] },  // TAG_DEPRECATED
		], diags);
	});

	it('does not report deprecated hint for non-deprecated imported symbol', () => {
		let diags = diagnose('file:///t.uc', "import { newFn } from 'deprecated';\nnewFn();\n");
		let depDiags = filter(diags, (d) => d.message === 'Deprecated');
		assert.match(0, length(depDiags));
	});

	it('reports unused-import hint for an import that is never used', () => {
		let src = cursors("import * as $1p$2 from 'parser';\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 4, 'unused-import', "'p' is imported but never used"),
		], diags);
	});

	it('does not report unused-import for an import that is used', () => {
		let diags = diagnose('file:///t.uc', "import * as p from 'parser';\np.parse;\n");
		let d = filter(diags, (d) => d.code === 'unused-import');
		assert.match(0, length(d));
	});

	it('reports redeclared-var error for duplicate let in same block', () => {
		let src = cursors("let x = 1;\nlet $1x$2 = 2;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 1, 'redeclared-var', "'x' is already declared in this scope"),
		], diags);
	});

	it('reports duplicate-key warning for duplicate object keys', () => {
		let src = cursors("let o = { a: 1, $1a$2: 2 };\no;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 2, 'duplicate-key', "Duplicate key 'a' in object literal"),
		], diags);
	});

	it('reports const-assignment error for reassigning a const variable', () => {
		let src = cursors("$3const$4 x = 1;\n$1x$2 = 2;\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([{
			...diagnostic(src, 1, 2, 1, 'const-assignment', "Cannot assign to 'x' — it is declared const"),
			data: { constKeywordRange: { start: src.at[3], end: src.at[4] } },  // for the quick fix
		}], diags);
	});

	it('reports missing-return warning for @returns function missing a path', () => {
		let src = cursors("/**\n * @returns {int}\n */\nfunction $1f$2() {\n  let x = 1;\n}\n");
		let diags = diagnose('file:///t.uc', src.text);
		let d = filter(diags, (d) => d.code === 'missing-return');
		assert.match([
			diagnostic(src, 1, 2, 2, 'missing-return', 'Not all code paths return a value'),
		], d);
	});

	it('reports for-in-non-iterable warning for iterating over an integer', () => {
		let src = cursors("for (let x in $142$2) { x; }\n");
		let diags = diagnose('file:///t.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 2, 'for-in-non-iterable', "Cannot iterate over type 'int'"),
		], diags);
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
		let src = cursors("let obj = { a: 1 };\nlet x = obj.$1b$2;\nx;\n");
		let diags = diagnose('file:///read_missing_key.uc', src.text);
		assert.match([
			diagnostic(src, 1, 2, 2, 'unknown-property', "Property 'b' does not exist on this type"),
		], diags);
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

		let src = cursors("import { $3foo$4 } from $1'bad_module'$2;");
		lsp.change(proc, 'file:///t.uc', src.text, 2);

		let diags = lsp.documentDiagnostics(proc, 'file:///t.uc').items;
		assert.match(any_order([
			diagnostic(src, 1, 2, 1, 'unknown-import', "Cannot find module 'bad_module'"),
			diagnostic(src, 3, 4, 4, 'unused-import', "'foo' is imported but never used"),
		]), diags);
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
