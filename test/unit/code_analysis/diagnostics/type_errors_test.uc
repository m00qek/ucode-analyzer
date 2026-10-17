import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { typeErrors } from 'code_analysis.diagnostics.type_errors';
import * as dag from 'code_analysis.dag.dag';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostics — type errors: call non-function', () => {
	it('reports no errors for a valid function call', () => {
		let doc = open("function foo() {}\nfoo();\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});

	it('reports error when calling a string variable', () => {
		let doc = open("let x = 'hello';\nx();\n");
		let diags = typeErrors(URI, doc);
		assert.match(true, length(diags) >= 1);
		let d = filter(diags, (d) => index(d.message, 'x') >= 0)[0];
		assert.match(true, d !== null);
		assert.match(1, d.severity);  // ERROR
	});

	it('reports error when calling a null variable', () => {
		let doc = open("let x = null;\nx();\n");
		let diags = typeErrors(URI, doc);
		let d = filter(diags, (d) => index(d.message, 'not a function') >= 0)[0];
		assert.match(true, d !== null);
		assert.match(1, d.severity);
	});

	it('error range covers the callee identifier', () => {
		let doc = open("let x = 'hello';\nx();\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'x') >= 0);
		let d = diags[0];
		assert.match(1, d.range.start.line);
		assert.match(0, d.range.start.character);
		assert.match(1, d.range.end.line);
		assert.match(1, d.range.end.character);
	});

	it('does not report error for calls to UNKNOWN-typed names (e.g. parameters)', () => {
		let doc = open("function f(cb) { cb(); }\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});

	it('does not report error for arrow function calls', () => {
		let doc = open("let fn = () => 42;\nfn();\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});
});

describe('diagnostics — type errors: member access on null', () => {
	it('reports error for member access on a provably-null variable', () => {
		let doc = open("let x = null;\nx.foo;\n");
		let diags = typeErrors(URI, doc);
		let d = filter(diags, (d) => d.code === 'null-access')[0];
		assert.match(true, d !== null);
		assert.match(1, d.severity);
		assert.match(true, index(d.message, 'is null') >= 0);
	});

	it('error range covers the object identifier', () => {
		let doc = open("let x = null;\nx.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'null-access');
		let d = diags[0];
		assert.match(1, d.range.start.line);
		assert.match(0, d.range.start.character);
	});

	it('does not report error for member access on non-null types', () => {
		let doc = open("function f() {}\nlet x = f;\n");
		// Accessing a property on an identifier typed as function is not null-like.
		// (UNKNOWN-typed accesses are also suppressed.)
		let diags = filter(typeErrors(URI, doc),
			(d) => d.code === 'null-access' || d.code === 'may-be-null');
		assert.match(0, length(diags));
	});
});

describe('diagnostics — type errors: flow sensitivity (if-body narrowing)', () => {
	it('suppresses null warning inside if (x) { } body', () => {
		let doc = open("let x = null;\nif (x) {\n  x.foo;\n}\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});

	it('suppresses null warning inside if (x !== null) { } body', () => {
		let doc = open("let x = null;\nif (x !== null) {\n  x.foo;\n}\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});

	it('still warns OUTSIDE the if-body when no guard clause exits', () => {
		let doc = open("let x = null;\nif (x) {\n  x.foo;\n}\nx.bar;\n");
		let diags = filter(typeErrors(URI, doc),
			(d) => d.code === 'null-access' || d.code === 'may-be-null');
		// bar access on line 4 is NOT guarded
		let outsideWarning = filter(diags, (d) => d.range.start.line === 4);
		assert.match(1, length(outsideWarning));
	});
});

describe('diagnostics — type errors: flow sensitivity (guard clause)', () => {
	it('suppresses null warning after if (!x) return guard clause', () => {
		let doc = open("let x = null;\nif (!x) return;\nx.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});

	it('suppresses null warning after if (!x) return guard clause', () => {
		let doc = open("let x = null;\nif (!x) return;\nx.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});

	it('still warns on line BEFORE the guard, where null is possible', () => {
		let doc = open("let x = null;\nx.foo;\nif (!x) return;\n");
		let diags = filter(typeErrors(URI, doc),
			(d) => d.code === 'null-access' || d.code === 'may-be-null');
		let beforeGuard = filter(diags, (d) => d.range.start.line === 1);
		assert.match(1, length(beforeGuard));
	});
});

describe('diagnostics — type errors: JSDoc @param type checking', () => {
	it('reports not-a-function when @param {string} param is called', () => {
		let doc = open("/** @param {string} name */\nfunction greet(name) { name(); }\n");
		let diags = typeErrors(URI, doc);
		let d = filter(diags, (d) => index(d.message, 'not a function') >= 0)[0];
		assert.match(true, d !== null);
		assert.match(1, d.severity);
	});

	it('does not report not-a-function for unannotated param (UNKNOWN stays callable)', () => {
		let doc = open("function f(cb) { cb(); }\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});

	it('reports not-a-function when @param {string} function declaration is used via multiline JSDoc', () => {
		let doc = open("/**\n * @param {string} name\n */\nfunction greet(name) { name(); }\n");
		let diags = typeErrors(URI, doc);
		let d = filter(diags, (d) => index(d.message, 'not a function') >= 0)[0];
		assert.match(true, d !== null);
	});
});

describe('diagnostics — type errors: for-in non-iterable', () => {
	it('no warning for for-in over an array', () => {
		let doc = open("let arr = [1,2,3];\nfor (let x in arr) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(0, length(diags));
	});

	it('no warning for for-in over a record', () => {
		let doc = open("let obj = { a: 1 };\nfor (let k in obj) { k; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(0, length(diags));
	});

	it('no warning for for-in over unknown type', () => {
		let doc = open("for (let x in mystery) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(0, length(diags));
	});

	it('warns for for-in over an integer literal', () => {
		let doc = open("for (let x in 42) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);  // WARNING
	});

	it('warns for for-in over a boolean literal', () => {
		let doc = open("for (let x in true) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(1, length(diags));
	});

	it('warns for for-in over null', () => {
		let doc = open("for (let x in null) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(1, length(diags));
	});

	it('warns for for-in over a const int variable', () => {
		let doc = open("const n = 42;\nfor (let x in n) { x; }\n");
		let diags = filter(typeErrors(URI, doc), (d) => d.code === 'for-in-non-iterable');
		assert.match(1, length(diags));
	});
});

describe('diagnostics — type errors: flow sensitivity (&& short-circuit)', () => {
	it('suppresses null warning on RHS of x && x.foo', () => {
		let doc = open("let x = null;\nlet y = x && x.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});

	it('suppresses null warning on RHS of x !== null && x.foo', () => {
		let doc = open("let x = null;\nlet y = x !== null && x.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		assert.match(0, length(diags));
	});
});

describe('diagnostics — type errors: unknown-property', () => {
	function unknownProps(text) {
		return filter(typeErrors(URI, open(text)), (d) => d.code === 'unknown-property');
	}

	it('warns for a missing field on a closed record literal', () => {
		assert.match(1, length(unknownProps("let o = { a: 1, b: 2 };\no.c;\n")));
	});

	it('no warning for delete of a possibly-absent property', () => {
		assert.match(0, length(unknownProps("let o = { a: 1 };\ndelete o.b;\n")));
	});

	it('no warning reading a field off an empty record', () => {
		assert.match(0, length(unknownProps("let e = {};\ne.foo;\n")));
	});

	it('no warning reading a field off a record spread from an untyped value', () => {
		assert.match(0, length(unknownProps("function f(x) {\n  let n = { ...x };\n  n.foo;\n}\n")));
	});

	it('still warns on a record spread only from a known record', () => {
		assert.match(1, length(unknownProps("let base = { a: 1 };\nlet m = { ...base };\nm.b;\n")));
	});

	it('no warning reading a property the file writes (objects are open)', () => {
		assert.match(0, length(unknownProps("let rv = { invert: false };\nrv.val = 1;\nprint(rv.val);\n")));
		assert.match(0, length(unknownProps("let n = { a: 1 };\nn.kids ??= {};\nn.kids.x = 1;\n")));
	});

	it('no warning reading before the write either', () => {
		assert.match(0, length(unknownProps("let o = { a: 1 };\nfunction get() { return o.b; }\no.b = 2;\n")));
	});

	it('knows the fields of fs.stat(), including perm', () => {
		dag.init({ workspaceDir: '/app', workspace: { libraryPaths: ['src'] } });
		function statProps(text) {
			dag.add(URI, text, documents.open(URI, text, 1).tree);
			let r = unknownProps(text);
			dag.remove(URI);
			return map(r, (d) => d.message);
		}
		assert.match([], statProps("import * as fs from 'fs';\nlet s = fs.stat('/');\nprint(s?.inode, s?.perm?.user_exec, s?.dev?.major);\n"));
		assert.match(["Property 'user_exec' does not exist on this type"],
			statProps("import * as fs from 'fs';\nlet s = fs.stat('/');\nprint(s?.user_exec);\n"));
	});

	it('still warns on a property written only on another object', () => {
		assert.match(1, length(unknownProps("let o = { a: 1 };\nlet p = {};\np.b = 2;\no.b;\n")));
	});
});

describe('diagnostics — type errors: discriminated unions', () => {
	function unknownProps(text) {
		return filter(typeErrors(URI, open(text)), (d) => d.code === 'unknown-property');
	}

	// f() returns a tagged union: {kind:'fail', value} | {kind:'pass'}
	let VARIANT_FN =
		"function f(c) {\n" +
		"  if (c) return { kind: 'fail', value: 1 };\n" +
		"  return { kind: 'pass' };\n" +
		"}\n";

	it('allows a field of the narrowed variant inside the guard', () => {
		assert.match(0, length(unknownProps(
			VARIANT_FN + "let r = f(1);\nif (r.kind === 'fail') { r.value; }\n")));
	});

	it('flags a field absent from the narrowed variant', () => {
		assert.match(1, length(unknownProps(
			VARIANT_FN + "let r = f(1);\nif (r.kind === 'fail') { r.nope; }\n")));
	});

	it('allows a field present on some variant of the un-narrowed union', () => {
		assert.match(0, length(unknownProps(
			VARIANT_FN + "let r = f(1);\nr.value;\n")));
	});

	it('flags a field absent from every variant of the un-narrowed union', () => {
		assert.match(1, length(unknownProps(
			VARIANT_FN + "let r = f(1);\nr.nope;\n")));
	});

	it('stays silent when any variant of the union is open', () => {
		let g = "function g(c, x) {\n" +
		        "  if (c) return { kind: 'a', a: 1 };\n" +
		        "  return { ...x };\n" +
		        "}\n";
		assert.match(0, length(unknownProps(g + "let u = g(1, {});\nu.zzz;\n")));
	});
});

describe('diagnostics — type errors: tiered null-safety', () => {
	function nullDiags(text) {
		return filter(typeErrors(URI, open(text)),
			(d) => d.code === 'null-access' || d.code === 'may-be-null');
	}

	it('a provably-null access is an error (code null-access)', () => {
		let d = nullDiags("let x = null;\nx.foo;\n")[0];
		assert.match(true, d !== null);
		assert.match('null-access', d.code);
		assert.match(1, d.severity);   // ERROR
		assert.match(true, index(d.message, 'is null') >= 0);
	});

	it('a possibly-null (T | null) access is a warning, not an error', () => {
		// A `?string` param is nullable: null is only one of its inhabitants.
		let d = nullDiags("/** @param {?string} s */\nfunction f(s) { return s.foo; }\n")[0];
		assert.match(true, d !== null);
		assert.match('may-be-null', d.code);
		assert.match(2, d.severity);   // WARNING
		assert.match(true, index(d.message, 'may be null') >= 0);
	});

	it('flags indexing a value that may be null', () => {
		let d = nullDiags("/** @param {?array} a */\nfunction f(a) { return a[0]; }\n");
		assert.match(['may-be-null'], map(d, (x) => x.code));
	});

	it('flags indexing a value that is null, read or write', () => {
		assert.match(['null-access'], map(nullDiags("let a = null;\na[0];\n"), (x) => x.code));
		assert.match(['null-access'], map(nullDiags("let a = null;\na[0] = 1;\n"), (x) => x.code));
	});

	it('does not flag ?.[ or an index after a null guard', () => {
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { return a?.[0]; }\n")));
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { if (!a) return; return a[0]; }\n")));
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { return a && a[0]; }\n")));
	});

	it("escalates a possibly-null access to an error under 'use strict'", () => {
		let d = nullDiags("'use strict';\n/** @param {?string} s */\nfunction f(s) { return s.foo; }\n")[0];
		assert.match(true, d !== null);
		assert.match('may-be-null', d.code);
		assert.match(1, d.severity);   // ERROR under strict
	});

	it("finds 'use strict' after a leading comment", () => {
		let d = nullDiags("// header\n'use strict';\n/** @param {?string} s */\nfunction f(s) { return s.foo; }\n")[0];
		assert.match(1, d.severity);
	});

	it("a provably-null access stays an error under 'use strict' too", () => {
		let d = nullDiags("'use strict';\nlet x = null;\nx.foo;\n")[0];
		assert.match(true, d !== null);
		assert.match('null-access', d.code);
		assert.match(1, d.severity);
	});

	it('a non-directive leading string does not enable strict mode', () => {
		// "hello" is not the strict directive, so possibly-null stays a warning.
		let d = nullDiags("'hello';\n/** @param {?string} s */\nfunction f(s) { return s.foo; }\n")[0];
		assert.match(true, d !== null);
		assert.match(2, d.severity);   // still WARNING
	});

	it('optional chaining on a provably-null value is not flagged', () => {
		// `x?.foo` short-circuits to null safely — no null-access.
		assert.match(0, length(nullDiags("let x = null;\nx?.foo;\n")));
	});

	it('optional chaining on a possibly-null value is not flagged', () => {
		// `s?.foo` is the null-safe form — no may-be-null warning.
		assert.match(0, length(nullDiags(
			"/** @param {?string} s */\nfunction f(s) { return s?.foo; }\n")));
	});
});
