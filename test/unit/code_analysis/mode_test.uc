import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { isTemplate, parse, topLevelStatements,
         importStmtSpecifier, importBindings, importBindingNodes,
         importRemoteName } from 'ucode_analyzer.code_analysis.mode';

// The first top-level import_statement in `text`.
function firstImport(text) {
	for (let s in topLevelStatements(ts.rootNode(parse(text))))
		if (ts.nodeType(s) === 'import_statement') return s;
	return null;
}

function stmtTypes(text) {
	let out = [];
	for (let s in topLevelStatements(ts.rootNode(parse(text))))
		push(out, ts.nodeType(s));
	return out;
}

describe('mode — isTemplate detection', () => {
	it('treats plain script code as non-template', () => {
		assert.match(false, isTemplate("let x = 1;\nprintf('%d', x);\n"));
	});

	it('does not flag a script whose string literal contains {{', () => {
		assert.match(false, isTemplate("let s = \"{{ not a tag }}\";\n"));
	});

	it('detects a statement tag at line start ({% %})', () => {
		assert.match(true, isTemplate("{% for (x in items): %}\n{% endfor %}\n"));
	});

	it('detects an expression tag at line start ({{ }})', () => {
		assert.match(true, isTemplate("{{ greeting }}\n"));
	});

	it('detects a comment tag at line start ({# #})', () => {
		assert.match(true, isTemplate("{# a note #}\nrest\n"));
	});

	it('detects a tag after leading whitespace', () => {
		assert.match(true, isTemplate("  \t{{ x }}\n"));
	});

	it('detects a tag with a trim marker ({%+ / {%- / {{-)', () => {
		assert.match(true, isTemplate("{%+ if (x): -%}\n{%- endif %}\n"));
	});

	// ── mid-line tags (code position), without regressing precision ──────────
	it('detects a mid-line expression tag not at the line start', () => {
		assert.match(true, isTemplate("prefix text {{ value }} suffix\n"));
	});

	it('detects a mid-line statement tag', () => {
		assert.match(true, isTemplate("some text {% x = 1 %}\n"));
	});

	it('does not flag a tag opener inside a line comment', () => {
		assert.match(false, isTemplate("// see {{ x }} for details\nlet y = 1;\n"));
	});

	it('does not flag a tag opener inside a block comment', () => {
		assert.match(false, isTemplate("/* template uses {% x %} */\nlet y = 1;\n"));
	});

	it('does not flag a tag opener inside a backtick string', () => {
		assert.match(false, isTemplate("let s = `a {{ b }} c`;\n"));
	});

	// ── shebang-driven mode (matches how ucode is actually invoked) ──────────
	it('treats a utpl shebang as template', () => {
		assert.match(true, isTemplate("#!/usr/bin/utpl\nplain text no tags\n"));
	});

	it('treats a `ucode -T` shebang as template', () => {
		assert.match(true, isTemplate("#!/usr/bin/ucode -T\nplain text\n"));
	});

	it('a `-R` shebang forces raw script even if a tag is present', () => {
		assert.match(false, isTemplate("#!/usr/bin/ucode -R\n{{ notATag }}\n"));
	});

	it('a plain ucode shebang with no flag falls through to content', () => {
		assert.match(false, isTemplate("#!/usr/bin/ucode\nlet x = 1;\n"));
		assert.match(true,  isTemplate("#!/usr/bin/ucode\n{% x %}\n"));
	});
});

describe('mode — parse dispatch', () => {
	it('parses a script with the ucode grammar (root: program)', () => {
		let tree = parse("let x = 1;\n");
		assert.match('program', ts.nodeType(ts.rootNode(tree)));
	});

	it('parses a template with the markup grammar (root: markup)', () => {
		let tree = parse("{{ x }}\n");
		assert.match('markup', ts.nodeType(ts.rootNode(tree)));
	});
});

describe('mode — topLevelStatements', () => {
	it('returns a script\'s top-level statements directly', () => {
		let types = stmtTypes("let a = 1;\nfunction f() {}\n");
		assert.match(true, index(types, 'lexical_declaration') >= 0);
		assert.match(true, index(types, 'function_declaration') >= 0);
	});

	it('surfaces a template\'s statements and drops the tag delimiters', () => {
		let types = stmtTypes("{% import { helper } from 'lib.util'; %}\n{{ y }}\n");
		// the import inside {% %} is surfaced; the delimiters are dropped
		assert.match(true, index(types, 'import_statement') >= 0);
		assert.match(false, index(types, 'statement_tag_open') >= 0);
		assert.match(false, index(types, 'statement_tag_close') >= 0);
	});

	it('drops the trim and lstrip delimiter variants too', () => {
		let types = stmtTypes("{%- let a = 1; -%}\n{%+ let b = 2; %}\n");
		assert.match(2, length(filter(types, (t) => t === 'lexical_declaration')));
		assert.match(0, length(filter(types, (t) => index(t, 'statement_tag_') === 0)));
	});

	it('surfaces every statement of a multi-statement tag', () => {
		let types = stmtTypes("{% let a = 1; let b = 2; %}\n");
		let lex = filter(types, (t) => t === 'lexical_declaration');
		assert.match(2, length(lex));
	});

	it('a spanning form is the ordinary statement', () => {
		let types = stmtTypes("{% for (x in xs): %}\n{{ x }}\n{% endfor %}\n");
		assert.match(true, index(types, 'for_in_alt_statement') >= 0);
	});
});

describe('mode — import structure', () => {
	let T = "import { a, b as c } from 'fs';\n";
	let N = "import * as fs from 'fs';\n";

	it('importStmtSpecifier returns the module string', () => {
		assert.match('fs', importStmtSpecifier(firstImport(T), T));
		assert.match('fs', importStmtSpecifier(firstImport(N), N));
	});

	it('importBindings decomposes named specifiers (remote/local nodes)', () => {
		let b = importBindings(firstImport(T));
		assert.match(null, b.namespaceAlias);
		assert.match(2, length(b.specifiers));
		// { a } — local === remote (same node).
		assert.match('a', ts.text(b.specifiers[0].remoteNode, T));
		assert.match('a', ts.text(b.specifiers[0].localNode, T));
		// { b as c } — remote b, local c.
		assert.match('b', ts.text(b.specifiers[1].remoteNode, T));
		assert.match('c', ts.text(b.specifiers[1].localNode, T));
	});

	it('importBindings exposes the namespace alias node', () => {
		let b = importBindings(firstImport(N));
		assert.match(0, length(b.specifiers));
		assert.match('fs', ts.text(b.namespaceAlias, N));
	});

	it('importBindingNodes yields the local binding names', () => {
		let names = map(importBindingNodes(firstImport(T)), (n) => ts.text(n, T));
		assert.match('a', names[0]);
		assert.match('c', names[1]);   // the local alias, not the remote `b`
		assert.match('fs', map(importBindingNodes(firstImport(N)), (n) => ts.text(n, N))[0]);
	});

	it('importBindings binds a default import under the remote name `default`', () => {
		let D = "import x, { y } from 'm';\n";
		let b = importBindings(firstImport(D));
		assert.match(['x', 'y'], map(b.specifiers, (s) => ts.text(s.localNode, D)));
		assert.match(['default', 'y'], map(b.specifiers, (s) => importRemoteName(s, D)));
		assert.match(['x', 'y'], map(importBindingNodes(firstImport(D)), (n) => ts.text(n, D)));
	});

	it('importRemoteName unquotes a string name and reads `default`', () => {
		let Q = "import { \"b-c\" as d, default as e } from 'm';\n";
		let b = importBindings(firstImport(Q));
		assert.match(['b-c', 'default'], map(b.specifiers, (s) => importRemoteName(s, Q)));
		assert.match(['d', 'e'], map(b.specifiers, (s) => ts.text(s.localNode, Q)));
	});

	it('importBindings skips a comment inside the braces', () => {
		let C = "import { /* c */ a } from 'm';\n";
		assert.match(['a'], map(importBindingNodes(firstImport(C)), (n) => ts.text(n, C)));
	});
});
