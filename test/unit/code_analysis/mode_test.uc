import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { isTemplate, parse, topLevelStatements } from 'code_analysis.mode';

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

	it('unwraps a statement tag to surface the inner statement', () => {
		let types = stmtTypes("{% import { helper } from 'lib.util'; %}\n{{ y }}\n");
		// the import inside {% %} is surfaced; the delimiters are dropped
		assert.match(true, index(types, 'import_statement') >= 0);
		assert.match(false, index(types, 'statement_tag_open') >= 0);
		assert.match(false, index(types, 'statement_tag') >= 0);
	});

	it('surfaces every statement of a multi-statement tag', () => {
		let types = stmtTypes("{% let a = 1; let b = 2; %}\n");
		let lex = filter(types, (t) => t === 'lexical_declaration');
		assert.match(2, length(lex));
	});

	it('passes a spanning form through as-is', () => {
		let types = stmtTypes("{% for (x in xs): %}\n{{ x }}\n{% endfor %}\n");
		assert.match(true, index(types, 'for_in_alt_statement') >= 0);
	});
});
