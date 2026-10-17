import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { stringLiteralText, identifierOccurrences } from 'ucode_analyzer.code_analysis.ast_text';
import { cursors } from 'cursor';

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
		let src = cursors("let $0x = 1;\n$1x;\n$2x;\n");
		// declaration + two uses, in source order
		assert.match({ x: src.offset }, idx(src.text, false));
	});

	it('counts shorthand property identifiers', () => {
		let src = cursors("let $0foo = 1;\nlet o = { $1foo };\n");
		assert.match(src.offset, idx(src.text, false).foo);
	});

	it('skipParams=false counts a formal parameter', () => {
		assert.match(true, exists(idx("function f(a) { return 1; }\n", false), 'a'));
	});

	it('skipParams=true skips formal parameters', () => {
		// the only `a` is the parameter, inside formal_parameters
		assert.match(false, exists(idx("function f(a) { return 1; }\n", true), 'a'));
	});

	it('skipParams=true still counts uses in the body', () => {
		let src = cursors("function f(a) { return $0a; }\n");
		// the body use only, not the param decl
		assert.match(src.offset, idx(src.text, true).a);
	});
});
