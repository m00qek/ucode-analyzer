import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { stringLiteralText, identifierOccurrences } from 'ucode_analyzer.code_analysis.ast_text';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

// The `string` node that is the value of `let x = <string>;`.
function stringNode(text) {
	let root = ts.rootNode(parse(text));
	let decl = ts.namedChild(ts.namedChild(root, 0), 0);  // lexical_declaration -> variable_declarator
	return ts.childByField(decl, 'value');
}

describe('ast_text — stringLiteralText', () => {
	it('returns the content of a plain string literal', () => {
		assert.match('hello', stringLiteralText(stringNode("let x = 'hello';"), "let x = 'hello';"));
	});

	it('returns the content of a double-quoted literal', () => {
		assert.match('a/b.c', stringLiteralText(stringNode('let x = "a/b.c";'), 'let x = "a/b.c";'));
	});

	it('yields empty string for an empty literal (no fragment child)', () => {
		assert.match('', stringLiteralText(stringNode('let x = "";'), 'let x = "";'));
	});

	it('concatenates fragments across an escape (raw fragments, escape byte dropped)', () => {
		// "a\nb" parses as fragment "a", escape, fragment "b" — stringLiteralText
		// joins only the fragments, so the raw content is "ab" (documented behavior;
		// callers use it for identifier-like content where escapes do not occur).
		let src = 'let x = "a\\nb";';
		assert.match('ab', stringLiteralText(stringNode(src), src));
	});
});

describe('ast_text — identifierOccurrences', () => {
	function idx(text, skipParams) {
		return identifierOccurrences(ts.rootNode(parse(text)), text, skipParams);
	}

	it('records every occurrence of a name with its start byte', () => {
		let m = idx("let x = 1;\nx;\nx;\n", false);
		assert.match(3, length(m.x));           // declaration + two uses
		// strictly increasing byte offsets
		assert.match(true, m.x[0] < m.x[1] && m.x[1] < m.x[2]);
	});

	it('counts shorthand property identifiers', () => {
		let m = idx("let foo = 1;\nlet o = { foo };\n", false);
		assert.match(true, length(m.foo) >= 2);
	});

	it('skipParams=false counts a formal parameter', () => {
		assert.match(true, exists(idx("function f(a) { return 1; }\n", false), 'a'));
	});

	it('skipParams=true skips formal parameters', () => {
		// the only `a` is the parameter, inside formal_parameters
		assert.match(false, exists(idx("function f(a) { return 1; }\n", true), 'a'));
	});

	it('skipParams=true still counts uses in the body', () => {
		let m = idx("function f(a) { return a; }\n", true);
		assert.match(1, length(m.a));           // the body use only, not the param decl
	});
});
