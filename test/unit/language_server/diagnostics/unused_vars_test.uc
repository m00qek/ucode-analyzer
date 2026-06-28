import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { unusedVars } from 'language_server.diagnostics.unused_vars';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

describe('diagnostics — unused variables', () => {
	it('returns empty list when every declared variable is used', () => {
		let text = "let x = 1;\nx;\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('warns for a let binding that is never referenced', () => {
		let text = "let unused = 1;\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));

		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);  // WARNING
		assert.match(true, index(diags[0].message, 'unused') >= 0);
	});

	it('warns for a const binding that is never referenced', () => {
		let text = "const MAX = 100;\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));

		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, 'MAX') >= 0);
	});

	it('warns for a function declaration that is never called', () => {
		let text = "function helper() { return 1; }\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));

		assert.match(1, length(diags));
		assert.match(true, index(diags[0].message, 'helper') >= 0);
	});

	it('does not warn for an exported function (consumed externally)', () => {
		let text = "export function api() { return 1; }\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('does not warn for an exported let binding', () => {
		let text = "export let VERSION = '1.0';\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('warning range covers only the identifier, not the whole declaration', () => {
		let text = "let unused = 42;\n";
		documents.open(URI, text, 1);

		let r = unusedVars(documents.get(URI))[0].range;

		// 'unused' starts at col 4
		assert.match(0, r.start.line);
		assert.match(4, r.start.character);
		assert.match(0, r.end.line);
		assert.match(10, r.end.character);  // 4 + len('unused')
	});

	it('does not warn for a variable used only in an inner function', () => {
		let text = "let x = 1;\nlet fn = () => x;\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);

		// x is used inside the arrow; fn is used by... wait, fn is never called
		// x: used → no warning. fn: never called → warning.
		assert.match(false, index(names, "'x' is declared but never used") >= 0);
	});

	it('detects unused variables declared inside a function body', () => {
		let text = "function outer() {\n  let inner_unused = 1;\n}\nouter();\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);

		assert.match(true, index(names, "'inner_unused' is declared but never used") >= 0);
	});

	it('warns when outer variable is shadowed by inner function param and never used outside', () => {
		// Outer x is never used (only the param declaration site shadows it).
		// Before fix: the x in formal_parameters was counted as a use → no warning.
		// After fix: formal_parameters is skipped → outer x has zero uses → warning.
		let text = "let x = 1;\nfunction f(x) { }\nf(2);\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));
		let xDiags = filter(diags, (d) => index(d.message, "'x'") >= 0);
		assert.match(true, length(xDiags) > 0);
	});

	it('does not warn when a variable is used as a shorthand property { x }', () => {
		let text = "let x = 1;\nlet obj = { x };\nobj;\n";
		documents.open(URI, text, 1);

		let diags = unusedVars(documents.get(URI));
		let xDiags = filter(diags, (d) => index(d.message, "'x'") >= 0);
		assert.match(0, length(xDiags));
	});

	it('does not warn when a variable shadows an outer one and the outer is used', () => {
		// outer x used on line 3; inner x used on line 2 — neither is unused
		let text = "let x = 1;\nfunction f() { let x = 2; return x; }\nx;\n";
		documents.open(URI, text, 1);

		// Note: our checker is name-based (not scope-aware), so it sees 'x' used
		// and reports 0 warnings for both bindings.
		let diags = unusedVars(documents.get(URI));
		let xDiags = filter(diags, (d) => index(d.message, "'x'") >= 0);
		assert.match(0, length(xDiags));
	});
});
