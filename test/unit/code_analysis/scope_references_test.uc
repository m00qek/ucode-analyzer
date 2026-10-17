import { describe, it, assert, any_order } from 'utest';
import * as ts from 'tree_sitter';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { anchorOf, referencesOf } from 'ucode_analyzer.code_analysis.scope_references';
import { cursors } from 'cursor';

// Marked text, parsed as a script or a template (mode.parse decides). $0 is
// the cursor; $1–$2, $3–$4, … mark the expected references.
function parsed(marked) {
	let src = cursors(marked);
	src.tree = mode.parse(src.text);
	src.root = ts.rootNode(src.tree);
	return src;
}

function spans(nodes) {
	return map(nodes, (n) => [ ts.startByte(n), ts.endByte(n) ]);
}

// The byte spans of the marker pairs $1–$2, $3–$4, … that src has.
function expected(src) {
	let out = [];
	for (let a = 1; a < 9; a += 2)
		if (src.offset[a] !== null) push(out, [ src.offset[a], src.offset[a + 1] ]);
	return out;
}

function refsAt(src, includeDeclaration) {
	let nodes = referencesOf(src.root, src.text, src.offset[0], includeDeclaration);
	return nodes ? spans(nodes) : null;
}

function anchorAt(src) {
	let a = anchorOf(src.root, src.text, src.offset[0]);
	if (a) a.anchorNode = a.anchorNode ? [ ts.startByte(a.anchorNode), ts.endByte(a.anchorNode) ] : null;
	return a;
}

describe('anchorOf', () => {
	it('anchors a declaration on itself', () => {
		let src = parsed("let $0$1count$2 = 0;\ncount;\n");
		assert.match({ targetName: 'count', anchorByte: src.offset[1], anchorNode: expected(src)[0] },
			anchorAt(src));
	});

	it('anchors a use on its declaration, from any byte of the name', () => {
		let src = parsed("let $1count$2 = 0;\nco$0unt;\n");
		assert.match({ targetName: 'count', anchorByte: src.offset[1], anchorNode: expected(src)[0] },
			anchorAt(src));
	});

	it('anchors a shadowed name on the nearest declaration', () => {
		let src = parsed("let x = 1;\nfunction f() {\n\tlet $1x$2 = 2;\n\treturn $0x;\n}\n");
		assert.match({ targetName: 'x', anchorByte: src.offset[1], anchorNode: expected(src)[0] },
			anchorAt(src));
	});

	it('anchors a use above an inner declaration on the outer one: no hoisting', () => {
		let src = parsed("let $1x$2 = 1;\nfunction f() {\n\t$0x;\n\tlet x = 2;\n}\n");
		assert.match({ targetName: 'x', anchorByte: src.offset[1], anchorNode: expected(src)[0] },
			anchorAt(src));
	});

	it('gives an undeclared name anchor -1 and no node', () => {
		assert.match({ targetName: 'print', anchorByte: -1, anchorNode: null },
			anchorAt(parsed("$0print(1);\n")));
	});

	it('returns null off an identifier', () => {
		// a keyword, a number, the byte just past a name, whitespace
		for (let marked in [ "$0let x = 1;\n", "let x = $01;\n", "let x$0 = 1;\n", "let x = 1;$0\n" ])
			assert.match(null, anchorAt(parsed(marked)), marked);
	});

	it('returns null past the end of the text', () => {
		let src = parsed("let x = 1;\n");
		assert.match(null, anchorOf(src.root, src.text, length(src.text) + 10));
	});

	it('returns null on names that bind nothing: a property, a key, an exported alias, an imported remote name', () => {
		for (let marked in [
			"let o = {};\no.$0x;\n",
			"let o = { $0x: 1 };\n",
			"let a = 1;\nexport { a as $0b };\n",
			"import { $0foo as bar } from 'm';\nbar;\n",
		])
			assert.match(null, anchorAt(parsed(marked)), marked);
	});
});

describe('referencesOf — binding forms', () => {
	// [ what, marked text ]: the references at $0 are the marked spans.
	let cases = [
		[ 'let, from a use', "let $1k$2 = 1;\nlet j = $3k$4 + $0$5k$6;\n" ],
		[ 'const', "const $1K$2 = 1;\n$0$3K$4;\n" ],
		[ 'a later declarator sees an earlier one', "let $0$1a$2 = 1, b = $3a$4;\n" ],
		[ 'a function declaration, its recursive call and a call',
			"function $1f$2() { return $3f$4(); }\n$0$5f$6();\n" ],
		[ 'a call above a function declaration is not its use',
			"f();\nfunction $0$1f$2() {}\n$3f$4();\n" ],
		[ 'a parameter shadows an outer name', "let a = 1;\nfunction f($1a$2, b) { return $0$3a$4 + b; }\na;\n" ],
		[ 'a rest parameter', "let rest;\nfunction f(x, ...$1rest$2) { return $0$3rest$4; }\nrest;\n" ],
		[ 'a bare arrow parameter, from its use', "let y = 0;\nlet f = $1y$2 => $0$3y$4 * 2;\ny;\n" ],
		[ 'a parenthesized arrow parameter', "let f = ($1p$2, q) => $0$3p$4 + q;\np;\n" ],
		[ 'the key of a two-variable for-in', "let k;\nfor (let $1k$2, v in {}) { $0$3k$4; v; }\nk;\n" ],
		[ 'the value of a two-variable for-in', "for (let k, $1v$2 in {}) { k; $0$3v$4; }\nv;\n" ],
		[ 'a for-in object is read in the outer scope', "let $0$1x$2 = [1];\nfor (let x in $3x$4) x;\n" ],
		[ 'a for-in without let uses the outer name', "let $1x$2;\nfor ($3x$4 in [1]) $0$5x$6;\n" ],
		[ 'a C-style for variable does not outlive the loop',
			"for (let $1i$2 = 0; $3i$4 < 2; $5i$6++) $0$7i$8;\ni;\n" ],
		[ 'a C-style for without let assigns the outer name',
			"let $1i$2;\nfor ($3i$4 = 0; $5i$6 < 2;) ;\n$0$7i$8;\n" ],
		[ 'a catch parameter does not outlive its clause', "try { f(); } catch ($1e$2) { $0$3e$4; }\ne;\n" ],
		[ 'a named import', "import { $1a$2 } from 'm';\n$0$3a$4();\n" ],
		[ 'an aliased import binds the alias', "import { foo as $1bar$2 } from 'm';\n$0$3bar$4();\nfoo;\n" ],
		[ 'a namespace import', "import * as $1ns$2 from 'm';\n$0$3ns$4.x;\n" ],
		[ 'a default import', "import $1d$2 from 'm';\n$0$3d$4;\n" ],
		[ 'an export alias uses the local name', "let $0$1a$2 = 1;\nexport { $3a$4 as b };\n" ],
		[ 'an exported function', "export function $1f$2() {}\n$0$3f$4();\n" ],
		[ 'a named function expression, from inside', "let f = function $1g$2() { return $0$3g$4; };\ng;\n" ],
		[ 'a template for-in loop variable', "{% let xs = [1]; for (let $1x$2 in xs): %}{{ $0$3x$4 }}{% endfor %}\n{{ x }}\n" ],
		[ 'a template C-style for variable',
			"{% for (let $1i$2 = 0; $3i$4 < 2; $5i$6++): %}{{ $0$7i$8 }}{% endfor %}\n" ],
		[ 'an undeclared name, from a use', "$1z$2;\nfunction f() { return $0$3z$4; }\n" ],
	];

	for (let c in cases) {
		let what = c[0], marked = c[1];
		it(what, () => {
			let src = parsed(marked);
			assert.match(any_order(expected(src)), refsAt(src));
		});
	}

	it('leaves a shorthand property out: renaming it would rename the key', () => {
		let src = parsed("let $0$1x$2 = 1;\nlet o = { x };\n$3x$4;\n");
		assert.match(any_order(expected(src)), refsAt(src));
	});

	it('leaves member properties and object keys out', () => {
		let src = parsed("let $0$1x$2 = 1;\nlet o = { x: 2 };\no.x;\n$3x$4;\n");
		assert.match(any_order(expected(src)), refsAt(src));
	});
});

describe('referencesOf — includeDeclaration', () => {
	it('leaves the declaration out when false, from a use', () => {
		let src = parsed("let x = 1;\n$1x$2;\n$0$3x$4;\n");
		assert.match(any_order(expected(src)), refsAt(src, false));
	});

	it('leaves the declaration out when false, from the declaration', () => {
		let src = parsed("function f($0x) { return $1x$2; }\n");
		assert.match([ [ src.offset[1], src.offset[2] ] ], refsAt(src, false));
	});

	it('includes the declaration when omitted or true', () => {
		let src = parsed("let $1x$2 = 1;\n$0$3x$4;\n");
		assert.match(any_order(expected(src)), refsAt(src));
		assert.match(any_order(expected(src)), refsAt(src, true));
	});

	it('keeps every use of an undeclared name, which has no declaration to drop', () => {
		let src = parsed("$1z$2;\n$0$3z$4;\n");
		assert.match(any_order(expected(src)), refsAt(src, false));
	});

	it('is empty for a name declared and never used', () => {
		assert.match([], refsAt(parsed("let $0x = 1;\n"), false));
	});
});

describe('referencesOf — off an identifier', () => {
	it('returns null', () => {
		for (let marked in [ "$0let x = 1;\n", "let x = 1;$0\n", "let o = { x: 1 };\no.$0x;\n" ])
			assert.match(null, refsAt(parsed(marked)), marked);
	});

	it('returns null on a shorthand property, which is not an identifier node', () => {
		assert.match(null, refsAt(parsed("let x = 1;\nlet o = { $0x };\n")));
	});

	it('returns null on an imported remote name, which is neither a binding nor a use', () => {
		assert.match(null, refsAt(parsed("import { $0foo as bar } from 'm';\n")));
	});
});
