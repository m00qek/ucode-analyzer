import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { isTemplate, parse } from 'code_analysis.mode';

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
