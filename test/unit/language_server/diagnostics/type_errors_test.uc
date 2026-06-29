import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { typeErrors } from 'language_server.diagnostics.type_errors';

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
	it('reports error for member access on a null variable', () => {
		let doc = open("let x = null;\nx.foo;\n");
		let diags = typeErrors(URI, doc);
		let d = filter(diags, (d) => index(d.message, 'may be null') >= 0)[0];
		assert.match(true, d !== null);
		assert.match(1, d.severity);
	});

	it('error range covers the object identifier', () => {
		let doc = open("let x = null;\nx.foo;\n");
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
		let d = diags[0];
		assert.match(1, d.range.start.line);
		assert.match(0, d.range.start.character);
	});

	it('does not report error for member access on non-null types', () => {
		let doc = open("function f() {}\nlet x = f;\n");
		// Accessing a property on an identifier typed as function is not null-like.
		// (UNKNOWN-typed accesses are also suppressed.)
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
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
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
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
		let diags = filter(typeErrors(URI, doc), (d) => index(d.message, 'may be null') >= 0);
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
