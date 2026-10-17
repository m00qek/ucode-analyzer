import { describe, it, assert, afterEach, contains, not } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { undefinedVars } from 'ucode_analyzer.code_analysis.diagnostics.undefined_var';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

let _config = fixture.config();

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
		assert.match(contains('ghost'), diags[0].message);
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
		assert.match(not(contains(["'a' is not defined"])), names);
		assert.match(not(contains(["'b' is not defined"])), names);
	});

	it('does not warn for a function parameter inside the function body', () => {
		let text = "function add(a, b) { return a + b; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);

		assert.match(not(contains(["'a' is not defined"])), names);
		assert.match(not(contains(["'b' is not defined"])), names);
	});

	it('does not warn for a for-in loop variable inside the loop body', () => {
		let text = "let arr = [];\nfor (let item in arr) { item; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'item' is not defined"])), names);
	});

	it('does not warn for a namespace import alias', () => {
		let text = "import * as ts from 'parser';\nts.parse;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'ts' is not defined"])), names);
	});

	it('does not warn for a named import', () => {
		let text = "import { parse } from 'parser';\nparse('x');\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'parse' is not defined"])), names);
	});

	it('does not warn for obj.prop — property identifiers are not variable refs', () => {
		let text = "let obj = {};\nobj.nonExistentProp;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'nonExistentProp' is not defined"])), names);
	});

	it('does warn for an undefined variable in a function body', () => {
		let text = "function f() { return ghost; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(contains(["'ghost' is not defined"]), names);
	});

	it('does not warn for a variable declared in an outer scope used in inner', () => {
		let text = "let x = 1;\nfunction f() { return x; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'x' is not defined"])), names);
	});

	it('does not warn for the loop variable in a C-style for condition', () => {
		let text = "for (let i = 0; i < 10; i++) { }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'i' is not defined"])), names);
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
		assert.match(contains(["'ghost' is not defined"]), names);
	});

	it('does not warn for the alias in export { foo as bar }', () => {
		let text = "let foo = 1;\nexport { foo as bar };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'bar' is not defined"])), names);
		assert.match(not(contains(["'foo' is not defined"])), names);
	});

	it('does warn when the local name in export { ghost as bar } is undefined', () => {
		let text = "export { ghost as bar };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(contains(["'ghost' is not defined"]), names);
	});

	it('does not warn for a catch variable inside a catch block', () => {
		let text = "try { } catch(e) { e; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'e' is not defined"])), names);
	});

	it('does not warn for a rest parameter used in the function body', () => {
		let text = "function f(...args) { return args; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'args' is not defined"])), names);
	});

	it('does not warn for a named function expression referring to itself recursively', () => {
		let text = "let f = function fact(n) { return n > 1 ? n * fact(n - 1) : 1; };\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'fact' is not defined"])), names);
	});

	it('does not warn for loop variable in a braceless for-in body', () => {
		let text = "let arr = [1];\nfor (let x in arr) x;\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'x' is not defined"])), names);
	});

	it('does not warn for the value variable in for (let k, v in obj)', () => {
		let text = "let obj = {};\nfor (let k, v in obj) { k; v; }\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'k' is not defined"])), names);
		assert.match(not(contains(["'v' is not defined"])), names);
	});

	it('does not warn for the loop variables of an alt-syntax for-in', () => {
		let text = "let obj = {};\nfor (let k, v in obj): k; v; endfor\n";
		documents.open(URI, text, 1);

		let diags = undefinedVars(documents.get(URI));
		let names = map(diags, (d) => d.message);
		assert.match(not(contains(["'k' is not defined"])), names);
		assert.match(not(contains(["'v' is not defined"])), names);
	});

	it('treats a default import as defined', () => {
		let text = "import x from 'fs';\nx;\n";
		documents.open(URI, text, 1);
		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('sees earlier declarators of a for initializer in later ones', () => {
		let text = "let xs = [5, 6];\nfor (let i = 0, x = xs[i]; i < 2; i++, x = xs[i]) print(x);\n";
		documents.open(URI, text, 1);
		assert.match(0, length(undefinedVars(documents.get(URI))));
	});

	it('knows the LuCI environment in a controller and a template', () => {
		let text = "let s = http.getenv('X');\nubus.call('a', 'b');\nprint(_('Hi'), ctx);\n";
		for (let uri in ['file:///usr/share/ucode/luci/controller/admin/x.uc',
		                 'file:///src/luci/modules/luci-base/ucode/template/y.ut']) {
			documents.open(uri, text, 1);
			assert.match(0, length(undefinedVars(documents.get(uri))));
			documents.close(uri);
		}
	});

	it('does not give the LuCI environment to other files', () => {
		let text = "http.getenv('X');\n";
		documents.open(URI, text, 1);
		assert.match(['http'], map(undefinedVars(documents.get(URI)), (d) => match(d.message, /'([^']+)'/)?.[1]));
	});

	it('reads extra globals from workspace.globals (list or glob map)', () => {
		let saved = dag.config();
		let a = fixture.uri('a.uc'), h = fixture.uri('www/h.uc'), other = fixture.uri('other.uc');
		dag.init(fixture.config({ globals: ['ext1'] }));
		documents.open(a, "ext1; ext2;\n", 1);
		assert.match(['ext2'], map(undefinedVars(documents.get(a)), (d) => match(d.message, /'([^']+)'/)?.[1]));
		dag.init(fixture.config({ globals: { 'www/**': ['uhttpd'] } }));
		documents.open(h, "uhttpd.recv;\n", 1);
		assert.match(0, length(undefinedVars(documents.get(h))));
		documents.open(other, "uhttpd.recv;\n", 1);
		assert.match(1, length(undefinedVars(documents.get(other))));
		for (let u in [a, h, other]) documents.close(u);
		dag.init(saved);
	});
});

