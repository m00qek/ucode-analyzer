import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { typeErrors } from 'ucode_analyzer.code_analysis.diagnostics.type_errors';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The whole diagnostic for the range between markers $0 and $1.
function diag(src, severity, code, message) {
	return { range: { start: src.at[0], end: src.at[1] }, severity, source: 'ucode-analyzer', code, message };
}

function startsAt(d, pos) {
	return d.range.start.line === pos.line && d.range.start.character === pos.character;
}

describe('diagnostics — type errors: call non-function', () => {
	it('reports no errors for a valid function call', () => {
		let doc = open("function foo() {}\nfoo();\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});

	it('reports error when calling a string variable', () => {
		let src = cursors("let x = 'hello';\n$0x$1();\n");
		assert.match([diag(src, 1, 'not-a-function', "'x' is not a function (type: string)")],
			typeErrors(URI, open(src.text)));
	});

	it('reports error when calling a null variable', () => {
		let src = cursors("let x = null;\n$0x$1();\n");
		assert.match([diag(src, 1, 'not-a-function', "'x' is not a function (type: null)")],
			typeErrors(URI, open(src.text)));
	});

	it('error range covers the callee identifier', () => {
		let src = cursors("let x = 'hello';\n$0x$1();\n");
		let diags = filter(typeErrors(URI, open(src.text)), (d) => index(d.message, 'x') >= 0);
		assert.match({ start: src.at[0], end: src.at[1] }, diags[0].range);
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
		let src = cursors("let x = null;\n$0x$1.foo;\n");
		assert.match([diag(src, 1, 'null-access', "'x' is null")], typeErrors(URI, open(src.text)));
	});

	it('error range covers the object identifier', () => {
		let src = cursors("let x = null;\n$0x$1.foo;\n");
		let diags = filter(typeErrors(URI, open(src.text)), (d) => d.code === 'null-access');
		assert.match({ start: src.at[0], end: src.at[1] }, diags[0].range);
	});

	it('does not report error for member access on non-null types', () => {
		// Accessing a property on an identifier typed as function is not null-like,
		// and UNKNOWN-typed accesses are suppressed.
		assert.match([], typeErrors(URI, open("function f() {}\nlet x = f;\nx.foo;\n")));
		assert.match([], typeErrors(URI, open("function f(p) { p.foo; }\n")));
	});
});

describe('diagnostics — type errors: flow sensitivity (if-body narrowing)', () => {
	it('suppresses null warning inside if (x) { } body', () => {
		let doc = open("let x = null;\nif (x) {\n  x.foo;\n}\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('suppresses null warning inside if (x !== null) { } body', () => {
		let doc = open("let x = null;\nif (x !== null) {\n  x.foo;\n}\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('still warns OUTSIDE the if-body when no guard clause exits', () => {
		// the bar access is NOT guarded
		let src = cursors("let x = null;\nif (x) {\n  x.foo;\n}\n$0x$1.bar;\n");
		assert.match([diag(src, 1, 'null-access', "'x' is null")], typeErrors(URI, open(src.text)));
	});
});

describe('diagnostics — type errors: flow sensitivity (guard clause)', () => {
	it('suppresses null warning after if (!x) return guard clause', () => {
		let doc = open("let x = null;\nif (!x) return;\nx.foo;\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('suppresses null warning after if (!x) return guard clause', () => {
		let doc = open("let x = null;\nif (!x) return;\nx.foo;\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('still warns on line BEFORE the guard, where null is possible', () => {
		let src = cursors("let x = null;\n$0x$1.foo;\nif (!x) return;\n");
		assert.match([diag(src, 1, 'null-access', "'x' is null")], typeErrors(URI, open(src.text)));
	});
});

describe('diagnostics — type errors: JSDoc @param type checking', () => {
	it('reports not-a-function when @param {string} param is called', () => {
		let src = cursors("/** @param {string} name */\nfunction greet(name) { $0name$1(); }\n");
		assert.match([diag(src, 1, 'not-a-function', "'name' is not a function (type: string)")],
			typeErrors(URI, open(src.text)));
	});

	it('does not report not-a-function for unannotated param (UNKNOWN stays callable)', () => {
		let doc = open("function f(cb) { cb(); }\n");
		assert.match(0, length(typeErrors(URI, doc)));
	});

	it('reports not-a-function when @param {string} function declaration is used via multiline JSDoc', () => {
		let src = cursors("/**\n * @param {string} name\n */\nfunction greet(name) { $0name$1(); }\n");
		assert.match([diag(src, 1, 'not-a-function', "'name' is not a function (type: string)")],
			typeErrors(URI, open(src.text)));
	});
});

describe('diagnostics — type errors: for-in non-iterable', () => {
	it('no warning for for-in over an array', () => {
		let doc = open("let arr = [1,2,3];\nfor (let x in arr) { x; }\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('no warning for for-in over a record', () => {
		let doc = open("let obj = { a: 1 };\nfor (let k in obj) { k; }\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('no warning for for-in over unknown type', () => {
		let doc = open("for (let x in mystery) { x; }\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('warns for for-in over an integer literal', () => {
		let src = cursors("for (let x in $042$1) { x; }\n");
		assert.match([diag(src, 2, 'for-in-non-iterable', "Cannot iterate over type 'int'")],  // WARNING
			typeErrors(URI, open(src.text)));
	});

	it('warns for for-in over a boolean literal', () => {
		let src = cursors("for (let x in $0true$1) { x; }\n");
		assert.match([diag(src, 2, 'for-in-non-iterable', "Cannot iterate over type 'boolean'")],
			typeErrors(URI, open(src.text)));
	});

	it('warns for for-in over null', () => {
		let src = cursors("for (let x in $0null$1) { x; }\n");
		assert.match([diag(src, 2, 'for-in-non-iterable', "Cannot iterate over type 'null'")],
			typeErrors(URI, open(src.text)));
	});

	it('warns for for-in over a const int variable', () => {
		let src = cursors("const n = 42;\nfor (let x in $0n$1) { x; }\n");
		assert.match([diag(src, 2, 'for-in-non-iterable', "Cannot iterate over type 'int'")],
			typeErrors(URI, open(src.text)));
	});
});

describe('diagnostics — type errors: flow sensitivity (&& short-circuit)', () => {
	it('suppresses null warning on RHS of x && x.foo', () => {
		let doc = open("let x = null;\nlet y = x && x.foo;\n");
		assert.match([], typeErrors(URI, doc));
	});

	it('suppresses null warning on RHS of x !== null && x.foo', () => {
		let doc = open("let x = null;\nlet y = x !== null && x.foo;\n");
		assert.match([], typeErrors(URI, doc));
	});
});

describe('diagnostics — type errors: unknown-property', () => {
	function unknownProps(text) {
		return filter(typeErrors(URI, open(text)), (d) => d.code === 'unknown-property');
	}

	it('warns for a missing field on a closed record literal', () => {
		let src = cursors("let o = { a: 1, b: 2 };\no.$0c$1;\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'c' does not exist on this type")],
			unknownProps(src.text));
	});

	it('knows the fields of a caught exception', () => {
		// die({ code: 1 }) puts the value in e.message: e.code is null.
		let src = cursors("try { die({ code: 1 }); } catch (e) { print(e.type, e.message, e.stacktrace, e.$0code$1); }\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'code' does not exist on this type")],
			unknownProps(src.text));
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
		let src = cursors("let base = { a: 1 };\nlet m = { ...base };\nm.$0b$1;\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'b' does not exist on this type")],
			unknownProps(src.text));
	});

	it('no warning reading a property the file writes (objects are open)', () => {
		assert.match(0, length(unknownProps("let rv = { invert: false };\nrv.val = 1;\nprint(rv.val);\n")));
		assert.match(0, length(unknownProps("let n = { a: 1 };\nn.kids ??= {};\nn.kids.x = 1;\n")));
	});

	it('no warning reading before the write either', () => {
		assert.match(0, length(unknownProps("let o = { a: 1 };\nfunction get() { return o.b; }\no.b = 2;\n")));
	});

	it('knows the fields of fs.stat(), including perm', () => {
		dag.init(fixture.config());
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
		let src = cursors("let o = { a: 1 };\nlet p = {};\np.b = 2;\no.$0b$1;\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'b' does not exist on this type")],
			unknownProps(src.text));
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
		let src = cursors(VARIANT_FN + "let r = f(1);\nif (r.kind === 'fail') { r.$0nope$1; }\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'nope' does not exist on this type")],
			unknownProps(src.text));
	});

	it('allows a field present on some variant of the un-narrowed union', () => {
		assert.match(0, length(unknownProps(
			VARIANT_FN + "let r = f(1);\nr.value;\n")));
	});

	it('flags a field absent from every variant of the un-narrowed union', () => {
		let src = cursors(VARIANT_FN + "let r = f(1);\nr.$0nope$1;\n");
		assert.match([diag(src, 2, 'unknown-property', "Property 'nope' does not exist on this type")],
			unknownProps(src.text));
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
		let src = cursors("let x = null;\n$0x$1.foo;\n");
		assert.match([diag(src, 1, 'null-access', "'x' is null")], nullDiags(src.text));   // ERROR
	});

	it('a possibly-null (T | null) access is a warning, not an error', () => {
		// A `?string` param is nullable: null is only one of its inhabitants.
		let src = cursors("/** @param {?string} s */\nfunction f(s) { return $0s$1.foo; }\n");
		assert.match([diag(src, 2, 'may-be-null', "'s' may be null")], nullDiags(src.text));   // WARNING
	});

	it('flags indexing a value that may be null', () => {
		let src = cursors("/** @param {?array} a */\nfunction f(a) { return $0a$1[0]; }\n");
		assert.match([diag(src, 2, 'may-be-null', "'a' may be null")], nullDiags(src.text));
	});

	it('flags indexing a value that is null, read or write', () => {
		let read = cursors("let a = null;\n$0a$1[0];\n");
		assert.match([diag(read, 1, 'null-access', "'a' is null")], nullDiags(read.text));
		let write = cursors("let a = null;\n$0a$1[0] = 1;\n");
		assert.match([diag(write, 1, 'null-access', "'a' is null")], nullDiags(write.text));
	});

	it('does not flag ?.[ or an index after a null guard', () => {
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { return a?.[0]; }\n")));
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { if (!a) return; return a[0]; }\n")));
		assert.match(0, length(nullDiags("/** @param {?array} a */\nfunction f(a) { return a && a[0]; }\n")));
	});

	it("escalates a possibly-null access to an error under 'use strict'", () => {
		let src = cursors("'use strict';\n/** @param {?string} s */\nfunction f(s) { return $0s$1.foo; }\n");
		assert.match([diag(src, 1, 'may-be-null', "'s' may be null")], nullDiags(src.text));   // ERROR under strict
	});

	it("finds 'use strict' after a leading comment", () => {
		let src = cursors("// header\n'use strict';\n/** @param {?string} s */\nfunction f(s) { return $0s$1.foo; }\n");
		assert.match([diag(src, 1, 'may-be-null', "'s' may be null")], nullDiags(src.text));
	});

	it("a provably-null access stays an error under 'use strict' too", () => {
		let src = cursors("'use strict';\nlet x = null;\n$0x$1.foo;\n");
		assert.match([diag(src, 1, 'null-access', "'x' is null")], nullDiags(src.text));
	});

	it('a non-directive leading string does not enable strict mode', () => {
		// "hello" is not the strict directive, so possibly-null stays a warning.
		let src = cursors("'hello';\n/** @param {?string} s */\nfunction f(s) { return $0s$1.foo; }\n");
		assert.match([diag(src, 2, 'may-be-null', "'s' may be null")], nullDiags(src.text));   // still WARNING
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

describe('diagnostics — type errors: values set elsewhere', () => {
	// [code, n] per diagnostic: n is the marker `$n` its range starts at (else
	// the start position itself).
	function codes(marked) {
		let src = cursors(marked);
		return map(typeErrors(URI, open(src.text)), (d) => {
			for (let n = 0; n < length(src.at); n++)
				if (src.at[n] && startsAt(d, src.at[n])) return [d.code, n];
			return [d.code, d.range.start];
		});
	}

	it('an outer variable assigned in another function may be null, not is null', () => {
		assert.match([['may-be-null', 0]], codes(
			"let marks = null;\nfunction use() { return $0marks[0]; }\nfunction init() { marks = [1]; return use(); }\ninit();\n"));
	});

	it('a guard on an outer variable assigned elsewhere clears it', () => {
		assert.match([], codes(
			"let marks = null;\nfunction use() { if (!marks) return 0; return marks[0]; }\nfunction init() { marks = [1]; return use(); }\ninit();\n"));
	});

	it('a field written elsewhere is not null-checked from its literal', () => {
		assert.match([], codes(
			"function parse(tags) {\n\tlet r = { typedef: null };\n\tfor (let t in tags)\n\t\tif (t) r.typedef = { type: null };\n" +
			"\tif (r.typedef && length(tags))\n\t\tr.typedef.type = 1;\n\treturn r;\n}\nparse([1]);\n"));
	});

	it('a returned object keeps the narrowing at its return', () => {
		assert.match([], codes(
			"function load(u) { return u ? { text: 'x' } : null; }\n" +
			"function f(us) { for (let u in us) { let doc = load(u); if (!doc) continue; return { u, doc }; } return null; }\n" +
			"function g(u) { let doc = load(u); if (!doc) return null; return { doc: doc }; }\n" +
			"let r = f([1]);\nif (r) print(r.doc.text);\nlet q = g(1);\nif (q) print(q.doc.text);\n"));
	});

	it('a variable filled with ??= or ||= is no longer null', () => {
		assert.match([], codes("let e = null;\ne ??= {};\nprint(e.x);\nlet o = null;\no ||= [];\nprint(o[0]);\n"));
		assert.match([], codes(
			"function outer() {\n\tlet d = null;\n\tfunction get() { d ??= {}; return d.x; }\n\treturn get;\n}\nouter();\n"));
	});

	it('reads a nested member of a returned record by its own type', () => {
		// c.range and c.range.start share a start and a node type.
		assert.match([], codes("function r(n) {\n\treturn { start: { line: n } };\n}\n" +
			"function item(n) {\n\treturn { range: r(n) };\n}\nlet c = item(1);\nprint(c.range.start.line + 1);\n"));
	});

	it('a field set in a callback, or added later, is not its literal type', () => {
		assert.match([], codes("function w(cb) { cb(); }\nfunction get() {\n\tlet out = { res: null };\n" +
			"\tw(() => { out.res = { d: 1 }; });\n\treturn out;\n}\nprint(get().res.d);\n"));
		assert.match([], codes("function sim() {\n\tlet s = { now: 1 };\n\ts.cycle = (o) => o;\n\treturn s;\n}\n" +
			"print(sim().cycle(1));\n"));
	});

	it('a variable read from an optional chain proves the chain root non-null', () => {
		assert.match([], codes("function parse(b) {\n\ttry { return json(b); } catch (e) { return null; }\n}\n" +
			"function call(raw) {\n\tlet body = parse(raw);\n\tlet code = body?.status?.code;\n" +
			"\tif (code == null)\n\t\treturn { outcome: 1 };\n\treturn { body };\n}\n" +
			"function one(raw) {\n\tlet r = call(raw);\n\tif (r.outcome)\n\t\treturn r.outcome;\n\treturn r.body.records;\n}\none('{}');\n"));
	});

	it('a type() mismatch that returns leaves the variable non-null', () => {
		assert.match([], codes("function f(raw) {\n\tlet m = json(raw)?.meta;\n\tif (type(m) != 'object')\n\t\treturn null;\n" +
			"\treturn m.name;\n}\nf('{}');\n"));
	});

	it('a variable assigned a value of unknown type is no longer null', () => {
		assert.match([], codes("function g(m) {\n\tlet p = null;\n\tp = m.make();\n\treturn () => p.go();\n}\ng({});\n"));
		assert.match([], codes("function g(m) {\n\tlet p = null;\n\tp = m.make();\n\treturn p.go();\n}\ng({});\n"));
	});

	it('a ??= in one branch leaves the variable possibly null', () => {
		assert.match([['may-be-null', 0]], codes("let e = null;\nlet c = time();\nif (c) e ??= {};\nprint($0e.x);\n"));
	});

	it('other compound assignments do not fill a null variable', () => {
		assert.match([['null-access', 0]], codes("let e = null;\ne += 1;\nprint($0e.x);\n"));
	});
});
