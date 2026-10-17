import { describe, it, assert, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { diagnosticsFor } from 'ucode_analyzer.code_analysis.diagnostics';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';

// Each diagnostic reads a template's code exactly as a script's: inside {% %}
// the code is the same statement stream. One snippet per pass.
const SNIPPETS = {
	'unused-var':             "let unused = 1;",
	'undefined-var':          "ghost();",
	'not-a-function':         "let s = 'x';\ns();",
	'const-assignment':       "const c = 1;\nc = 2;\nprint(c);",
	'duplicate-key':          "let o = { a: 1, a: 2 };\nprint(o);",
	'redeclared-var':         "let x = 1;\nlet x = 2;\nprint(x);",
	'prefer-strict-equality': "let a = 1;\nif (a == 2) print(a);",
	'unreachable-code':       "function f() { return 1; print(2); }\nf();",
	'format-argument-count':  "printf('%d %d\\n', 1);",
	'unknown-import-symbol':  "import { nope } from 'tree_sitter';\nprint(nope);",
	'null-access':            "let n = null;\nprint(n.x);",
	'jsdoc-param-mismatch':   "/**\n * @param {int} a\n */\nfunction f(b) { return b; }\nf(1);",
	'missing-return':         "/** @returns {int} */\nfunction f(x) { if (x) return 1; }\nf(1);",
	'syntax-error':           "let = ;",
};

const GLOBAL = 'file:///app/src/ucode_analyzer/declarations/global.d.uc';
dag.init({ workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src'] } });
dag.addFromDisk(GLOBAL);
initBuiltinsFromDag(GLOBAL);

function codes(uri, text) {
	dag.add(uri, text, documents.open(uri, text, 1).tree);
	let out = sort(map(diagnosticsFor(uri, documents.get(uri)), (d) => d.code));
	documents.close(uri);
	dag.remove(uri);
	return out;
}

describe('diagnostics — templates read like scripts', () => {
	for (let n, c in SNIPPETS) {
		// A closure sees a loop variable's last value; a block's `let` is per pass.
		let name = n, code = c;
		it(name, () => {
			let script = codes('file:///script.uc', code);
			let template = codes('file:///template.uc', "{%\n" + code + "\n%}\n");
			assert.match(contains([name]), script);
			assert.match(script, template);
		});
	}
});
