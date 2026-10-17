import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { unusedVars } from 'ucode_analyzer.code_analysis.diagnostics.unused_var';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// The warning for `name` declared between markers $0 and $1.
function unused(src, name) {
	return { range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
		code: 'unused-var', message: sprintf("'%s' is declared but never used", name) };
}

function check(marked) {
	let src = cursors(marked);
	documents.open(URI, src.text, 1);
	return { src, diags: unusedVars(documents.get(URI)) };
}

describe('diagnostics — unused variables', () => {
	it('returns empty list when every declared variable is used', () => {
		let text = "let x = 1;\nx;\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('warns for a let binding that is never referenced', () => {
		let r = check("let $0unused$1 = 1;\n");
		assert.match([unused(r.src, 'unused')], r.diags);  // a WARNING
	});

	it('warns for a const binding that is never referenced', () => {
		let r = check("const $0MAX$1 = 100;\n");
		assert.match([unused(r.src, 'MAX')], r.diags);
	});

	it('warns for a function declaration that is never called', () => {
		let r = check("function $0helper$1() { return 1; }\n");
		assert.match([unused(r.src, 'helper')], r.diags);
	});

	it('does not warn for an exported function (consumed externally)', () => {
		let text = "export function api() { return 1; };\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('does not warn for an exported let binding', () => {
		let text = "export let VERSION = '1.0';\n";
		documents.open(URI, text, 1);

		assert.match(0, length(unusedVars(documents.get(URI))));
	});

	it('warning range covers only the identifier, not the whole declaration', () => {
		let r = check("let $0unused$1 = 42;\n");
		assert.match([unused(r.src, 'unused')], r.diags);
	});

	it('does not warn for a variable used only in an inner function', () => {
		// x is used inside the arrow; fn is never called, so only fn is flagged.
		let r = check("let x = 1;\nlet $0fn$1 = () => x;\n");
		assert.match([unused(r.src, 'fn')], r.diags);
	});

	it('detects unused variables declared inside a function body', () => {
		let r = check("function outer() {\n  let $0inner_unused$1 = 1;\n}\nouter();\n");
		assert.match([unused(r.src, 'inner_unused')], r.diags);
	});

	it('warns for a variable declared inside an if-body that is never used', () => {
		let r = check("if (true) { let $0inner_unused$1 = 1; }\n");
		assert.match([unused(r.src, 'inner_unused')], r.diags);
	});

	it('warns when outer variable is shadowed by inner function param and never used outside', () => {
		// Outer x is never used (only the param declaration site shadows it).
		// Before fix: the x in formal_parameters was counted as a use → no warning.
		// After fix: formal_parameters is skipped → outer x has zero uses → warning.
		let r = check("let $0x$1 = 1;\nfunction f(x) { }\nf(2);\n");
		assert.match([unused(r.src, 'x')], r.diags);
	});

	it('does not warn when a variable is used as a shorthand property { x }', () => {
		assert.match([], check("let x = 1;\nlet obj = { x };\nobj;\n").diags);
	});

	it('does not warn when a variable shadows an outer one and the outer is used', () => {
		// outer x used on line 3; inner x used on line 2 — neither is unused
		// (only f, never called, is).
		let r = check("let x = 1;\nfunction $0f$1() { let x = 2; return x; }\nx;\n");
		assert.match([unused(r.src, 'f')], r.diags);
	});

});
