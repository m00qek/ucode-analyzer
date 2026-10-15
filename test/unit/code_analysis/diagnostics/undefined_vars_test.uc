import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { undefinedVars } from 'code_analysis.diagnostics.undefined_vars';
import * as dag from 'code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'code_analysis.types.dag_bridge';

let URI = 'file:///test.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

// Bootstrap stdlib once so undefinedVars can distinguish builtins from
// truly undefined names.
dag.init(_config);
let _globalUri = dag.resolveSpecifier('global');
if (_globalUri) {
	dag.addFromDisk(_globalUri);
	initBuiltinsFromDag(_globalUri);
}

afterEach(() => documents.close(URI));

describe('diagnostics — undefined variables', () => {
	it('returns empty list when all identifiers are defined', () => {
		let text = "let x = 1;\nx;\n";
		documents.open(URI, text, 1);

		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('warns for an identifier that has no declaration anywhere', () => {
		let text = "ghost;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));

		assert.match(1, length(diags));
		assert.match(2, diags[0].severity);  // WARNING
		assert.match(true, index(diags[0].message, 'ghost') >= 0);
	});

	it('does not warn for stdlib builtins', () => {
		let text = "push([], 1);\nlength([]);\nmap([], x => x);\n";
		documents.open(URI, text, 1);

		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('does not warn for a locally declared let variable', () => {
		let text = "let count = 0;\ncount;\n";
		documents.open(URI, text, 1);

		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('does not warn for a locally declared function', () => {
		let text = "function greet() { return 1; }\ngreet();\n";
		documents.open(URI, text, 1);

		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('does not warn for params of a named function expression', () => {
		let text = "let f = function myFunc(a, b) { return a + b; };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'a' is not defined") >= 0);
		assert.match(false, index(names, "'b' is not defined") >= 0);
	});

	it('does not warn for a function parameter inside the function body', () => {
		let text = "function add(a, b) { return a + b; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);

		assert.match(false, index(names, "'a' is not defined") >= 0);
		assert.match(false, index(names, "'b' is not defined") >= 0);
	});

	it('does not warn for a for-in loop variable inside the loop body', () => {
		let text = "let arr = [];\nfor (let item in arr) { item; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'item' is not defined") >= 0);
	});

	it('does not warn for a namespace import alias', () => {
		let text = "import * as ts from 'tree_sitter';\nts.parse;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'ts' is not defined") >= 0);
	});

	it('does not warn for a named import', () => {
		let text = "import { parse } from 'tree_sitter';\nparse('x');\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'parse' is not defined") >= 0);
	});

	it('does not warn for obj.prop — property identifiers are not variable refs', () => {
		let text = "let obj = {};\nobj.nonExistentProp;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'nonExistentProp' is not defined") >= 0);
	});

	it('does warn for an undefined variable in a function body', () => {
		let text = "function f() { return ghost; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(true, index(names, "'ghost' is not defined") >= 0);
	});

	it('does not warn for a variable declared in an outer scope used in inner', () => {
		let text = "let x = 1;\nfunction f() { return x; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'x' is not defined") >= 0);
	});

	it('does not warn for the loop variable in a C-style for condition', () => {
		let text = "for (let i = 0; i < 10; i++) { }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'i' is not defined") >= 0);
	});

	it('does not warn for the loop variable in a C-style for increment', () => {
		let text = "for (let i = 0; i < 10; i++) { }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let msgs = filter(diags, (d) => index(d.message, "'i'") >= 0);
		assert.match(0, length(msgs));
	});

	it('warns for undefined reference in C-style for initializer value', () => {
		let text = "for (let i = ghost; i < 10; i++) { }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(true, index(names, "'ghost' is not defined") >= 0);
	});

	it('does not warn for the alias in export { foo as bar }', () => {
		let text = "let foo = 1;\nexport { foo as bar };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'bar' is not defined") >= 0);
		assert.match(false, index(names, "'foo' is not defined") >= 0);
	});

	it('does warn when the local name in export { ghost as bar } is undefined', () => {
		let text = "export { ghost as bar };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(true, index(names, "'ghost' is not defined") >= 0);
	});

	it('does not warn for a catch variable inside a catch block', () => {
		let text = "try { } catch(e) { e; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'e' is not defined") >= 0);
	});

	it('does not warn for a rest parameter used in the function body', () => {
		let text = "function f(...args) { return args; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'args' is not defined") >= 0);
	});

	it('does not warn for a named function expression referring to itself recursively', () => {
		let text = "let f = function fact(n) { return n > 1 ? n * fact(n - 1) : 1; };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'fact' is not defined") >= 0);
	});

	it('does not warn for loop variable in a braceless for-in body', () => {
		let text = "let arr = [1];\nfor (let x in arr) x;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'x' is not defined") >= 0);
	});

	it('does not warn for the value variable in for (let k, v in obj)', () => {
		let text = "let obj = {};\nfor (let k, v in obj) { k; v; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'k' is not defined") >= 0);
		assert.match(false, index(names, "'v' is not defined") >= 0);
	});

	it('does not warn for the loop variables of an alt-syntax for-in', () => {
		let text = "let obj = {};\nfor (let k, v in obj): k; v; endfor\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(false, index(names, "'k' is not defined") >= 0);
		assert.match(false, index(names, "'v' is not defined") >= 0);
	});
});
