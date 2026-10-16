import { describe, it, assert, beforeEach, prop, gen } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'code_analysis.dag.dag';
import * as mode from 'code_analysis.mode';
import { initBuiltinsFromDag } from 'code_analysis.types.dag_bridge';
import { buildScopeMap, scopeAtOffset } from 'code_analysis.types.scope_walk';
import { scopeGet } from 'code_analysis.types.scope';
import { invalidateUri } from 'code_analysis.memo';

let _parser = ts.newParser(ts.ucode());

function parse(text) {
	return ts.parse(_parser, text);
}

let URI = 'file:///app/src/test_walk.uc';

let _config = {
	workspaceDir: '/app',
	workspace: { libraryPaths: ['src'] },
};

dag.init(_config);
let _globalUri = dag.resolveSpecifier('global');
if (_globalUri) {
	dag.addFromDisk(_globalUri);
	initBuiltinsFromDag(_globalUri);
}

beforeEach(() => { invalidateUri(URI); });

// Build a scope map for `src` and look up the scope at the start of `marker`.
// The checkpoint at startByte(stmt) already reflects all prior declarations,
// so this gives the scope that `marker`'s statement sees on entry.
function scopeAt(src, marker) {
	let tree = parse(src);
	let map  = buildScopeMap(URI, src, tree);
	return scopeAtOffset(map, index(src, marker));
}

// Template variant: parse via mode (markup grammar) and look up the scope at the
// start of `marker`.
function scopeAtTpl(src, marker) {
	let tree = mode.parse(src);
	let map  = buildScopeMap(URI, src, tree);
	return scopeAtOffset(map, index(src, marker));
}

// ── basic declarations ────────────────────────────────────────────────────────

describe('buildScopeMap basic declarations', () => {
	it('variable not visible before its declaration', () => {
		let src = 'let x = 1;\nlet y = 2;\n';
		// At the start of 'let y', x is already in scope but y is not.
		let scope = scopeAt(src, 'let y');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'x'));
		assert.match(null, scopeGet(scope, 'y'));
	});

	it('variable visible after its declaration', () => {
		let src = 'let x = 1;\nlet y = 2;\n';
		let scope = scopeAt(src, 'let y');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'x'));
	});

	it('second variable not visible during first initializer', () => {
		let src = 'let x = 1, y = 2;\n';
		// At the start of the declaration x is not yet in scope
		let scope = scopeAt(src, 'let x');
		assert.match(null, scopeGet(scope, 'x'));
		assert.match(null, scopeGet(scope, 'y'));
	});

	it('function declaration visible after it', () => {
		let src = 'function f() {}\nlet x = 1;\n';
		let scope = scopeAt(src, 'let x');
		assert.match('function', scopeGet(scope, 'f')?.kind);
	});
});

// ── nested blocks ─────────────────────────────────────────────────────────────

describe('buildScopeMap nested blocks', () => {
	it('inner declaration not visible in outer scope', () => {
		let src = 'let x = 1;\n{\n  let inner = 2;\n}\nlet z = 3;\n';
		// After the block, 'inner' should not be visible
		let scope = scopeAt(src, 'let z');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'x'));
		assert.match(null, scopeGet(scope, 'inner'));
	});

	it('outer declarations visible inside block', () => {
		let src = 'let x = 1;\n{\n  let y = x;\n}\n';
		let scope = scopeAt(src, 'let y');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'x'));
	});
});

// ── if-statement narrowing ────────────────────────────────────────────────────

describe('buildScopeMap between statements', () => {
	function at(src, offset) {
		return scopeAtOffset(buildScopeMap(URI, src, parse(src)), offset);
	}

	it('a blank line after a block\'s last let sees it', () => {
		let src = 'function f(a) {\n  let y = 1;\n  \n}\n';
		assert.match('int', scopeGet(at(src, index(src, '  \n}') + 2), 'y')?.name);
	});

	it('a blank line between top-level statements sees the earlier let', () => {
		let src = 'let z = 1;\n\nprint(z);\n';
		assert.match('int', scopeGet(at(src, index(src, '\n\n') + 1), 'z')?.name);
	});

	it('a block\'s let is gone after the block closes', () => {
		let src = 'function f() {\n  let y = 1;\n}\n\nprint(1);\n';
		assert.match(null, scopeGet(at(src, index(src, '}\n\n') + 2), 'y'));
	});

	it('a guard clause narrows the blank line after it', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (!m) return;\n  \n}\n';
		assert.match('string', scopeGet(at(src, index(src, '  \n}') + 2), 'm')?.name);
	});
});

describe('buildScopeMap switch', () => {
	let P = '/** @param {?array} m */\nfunction f(m, k) {\n';

	it('a let inside a case is in scope for the rest of the clause', () => {
		let src = "function f(x) {\n\tswitch (x) {\n\tcase 1:\n\t\tlet y = 'a';\n\t\treturn y;\n\t}\n}\n";
		assert.match('string', scopeGet(scopeAt(src, 'return y'), 'y')?.name);
	});

	it('a case with a non-null label narrows X in switch (X?.[i])', () => {
		let src = P + "\tswitch (m?.[1]) {\n\tcase 'a':\n\t\tlet x = m;\n\t\tbreak;\n\tdefault:\n\t\tlet z = m;\n\t}\n}\n";
		assert.match('ref', scopeGet(scopeAt(src, 'let x'), 'm')?.kind);
		assert.match('nullable', scopeGet(scopeAt(src, 'let z'), 'm')?.kind);
	});

	it('does not narrow a case that default falls into', () => {
		let src = P + "\tswitch (m?.[1]) {\n\tdefault:\n\t\tk();\n\tcase 'a':\n\t\tlet x = m;\n\t}\n}\n";
		assert.match('nullable', scopeGet(scopeAt(src, 'let x'), 'm')?.kind);
	});

	it('narrows through fallthrough between narrowed cases', () => {
		let src = P + "\tswitch (m?.[1]) {\n\tcase 'a':\n\t\tk();\n\tcase 'b':\n\t\tlet x = m;\n\t}\n}\n";
		assert.match('ref', scopeGet(scopeAt(src, 'let x'), 'm')?.kind);
	});

	it('a case null label does not narrow', () => {
		let src = P + "\tswitch (m?.[1]) {\n\tcase null:\n\t\tlet x = m;\n\t}\n}\n";
		assert.match('nullable', scopeGet(scopeAt(src, 'let x'), 'm')?.kind);
	});
});

describe('buildScopeMap @type', () => {
	it('types a declaration by its @type over the initializer', () => {
		let src = '/** @type {string} */\nlet x = foo();\nlet y = 1;\n';
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scopeAt(src, 'let y'), 'x'));
	});

	it('types every variable of the declaration', () => {
		let src = '/** @type {?int} */\nlet a, b = 2;\nlet y = 1;\n';
		let scope = scopeAt(src, 'let y');
		assert.match('nullable', scopeGet(scope, 'a')?.kind);
		assert.match('nullable', scopeGet(scope, 'b')?.kind);
	});
});

describe('buildScopeMap if-statement narrowing', () => {
	it('nullable variable narrowed to non-null in consequent', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (m) {\n    let x = m;\n  }\n}\n';
		let scope = scopeAt(src, 'let x');
		let mType = scopeGet(scope, 'm');
		assert.match('primitive', mType?.kind);
		assert.match('string', mType?.name);
	});

	it('narrowing does not bleed into else branch', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (m) {}\n  else {\n    let x = 1;\n  }\n}\n';
		let scope = scopeAt(src, 'let x');
		let mType = scopeGet(scope, 'm');
		// In the else branch the falsy guard sets m to null.
		assert.match({ kind: 'primitive', name: 'null' }, mType);
	});

	it('narrows on a condition that starts with a comment', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (/* set? */ m) {\n    let x = m;\n  }\n}\n';
		assert.match('string', scopeGet(scopeAt(src, 'let x'), 'm')?.name);
	});

	it('narrows after a guard clause whose block ends in a comment', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (!m) { return; /* bail */ }\n  let x = m;\n}\n';
		assert.match('string', scopeGet(scopeAt(src, 'let x'), 'm')?.name);
	});

	it('a guard clause with || narrows after it', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (!m || length(m) > 9) return;\n  let x = m;\n}\n';
		assert.match('string', scopeGet(scopeAt(src, 'let x'), 'm')?.name);
	});

	it('the else branch of a || condition narrows; the then branch does not', () => {
		let src = '/** @param {string|null} m */\nfunction f(m, k) {\n  if (!m || k) {\n    let t = 1;\n  } else {\n    let x = m;\n  }\n}\n';
		assert.match('string', scopeGet(scopeAt(src, 'let x'), 'm')?.name);
		assert.match('union', scopeGet(scopeAt(src, 'let t'), 'm')?.kind);
	});

	it('compound && guard narrows in body', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (m && type(m) === "string") {\n    let x = m;\n  }\n}\n';
		let scope = scopeAt(src, 'let x');
		let mType = scopeGet(scope, 'm');
		// The truthy sub-guard in the && narrows m to non-null string.
		assert.match({ kind: 'primitive', name: 'string' }, mType);
	});
});

// ── colon / endif (alt-form) if narrowing in a plain script ─────────────────────

describe('buildScopeMap colon-form if/elif narrowing', () => {
	// `if (…): … elif (…): … endif` in a script parses to if_alt_statement with
	// inline elif_clause bodies (no {% %} tags). Each branch must see its OWN
	// guard, not inherit the previous branch's narrowing.
	it('narrows the if body and does not leak that narrowing into the elif body', () => {
		let src = "let m = (1 > 0) ? 'x' : null;\n" +
		          "if (m):\n\tlet a = m;\n" +
		          "elif (m == null):\n\tlet b = m;\n" +
		          "endif;\n";
		// if body: m truthy → non-null string
		assert.match('string', scopeGet(scopeAt(src, 'let a'), 'm')?.name);
		// elif body: its own guard (m == null) → null; NOT the if body's string
		assert.match({ kind: 'primitive', name: 'null' }, scopeGet(scopeAt(src, 'let b'), 'm'));
	});
});

// ── ternary narrowing ─────────────────────────────────────────────────────────

describe('buildScopeMap ternary narrowing', () => {
	it('nullable narrowed in ternary consequent', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  let r = m ? m : "default";\n}\n';
		// At the first `m` after `?`, m should be narrowed
		let tree = parse(src);
		let map  = buildScopeMap(URI, src, tree);
		// Find the offset of the consequent `m` (after the `?`)
		let qmark = index(src, '? m');
		let scope = scopeAtOffset(map, qmark + 2);
		let mType = scopeGet(scope, 'm');
		assert.match('primitive', mType?.kind);
		assert.match('string', mType?.name);
	});
});

// ── function parameters ───────────────────────────────────────────────────────

describe('buildScopeMap function parameters', () => {
	it('params visible inside function body', () => {
		let src = '/** @param {int} x @param {string} y */\nfunction f(x, y) {\n  let z = 1;\n}\n';
		let scope = scopeAt(src, 'let z');
		assert.match({ kind: 'primitive', name: 'int' },    scopeGet(scope, 'x'));
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'y'));
	});

	it('params not visible outside function body', () => {
		let src = '/** @param {int} x */\nfunction f(x) {}\nlet z = 1;\n';
		let scope = scopeAt(src, 'let z');
		assert.match(null, scopeGet(scope, 'x'));
	});

	it('arrow function params visible in expression body', () => {
		// JSDoc on inline arrow expressions is not inferred; the param will be unknown.
		// What matters is that the param IS in scope inside the expression body.
		let src = 'let f = (n) => n + 1;\n';
		let tree = parse(src);
		let map  = buildScopeMap(URI, src, tree);
		let bodyOff = index(src, 'n + 1');
		let scope = scopeAtOffset(map, bodyOff);
		assert.match('unknown', scopeGet(scope, 'n')?.kind);
	});
});

// ── for-in loop variable ──────────────────────────────────────────────────────

describe('buildScopeMap for-in loop variable', () => {
	it('loop variable visible inside body', () => {
		let src = 'let arr = [];\nfor (let k in arr) {\n  let x = k;\n}\n';
		let scope = scopeAt(src, 'let x');
		// k is in scope; type is unknown because arr is an untyped empty array.
		assert.match('unknown', scopeGet(scope, 'k')?.kind);
	});

	it('loop variable not visible after loop', () => {
		let src = 'let arr = [];\nfor (let k in arr) {}\nlet z = 1;\n';
		let scope = scopeAt(src, 'let z');
		assert.match(null, scopeGet(scope, 'k'));
	});
});

// ── for-statement initializer ─────────────────────────────────────────────────

describe('buildScopeMap for-statement', () => {
	it('initializer variable visible inside body', () => {
		let src = 'for (let i = 0; i < 10; i++) {\n  let x = i;\n}\n';
		let scope = scopeAt(src, 'let x');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'i'));
	});
});

// ── catch variable ────────────────────────────────────────────────────────────

describe('buildScopeMap catch variable', () => {
	it('catch parameter visible inside catch body', () => {
		let src = 'try {\n  let x = 1;\n} catch (e) {\n  let y = e;\n}\n';
		let scope = scopeAt(src, 'let y');
		// catch param is always typed as string (error message).
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'e'));
	});

	it('catch parameter not visible outside', () => {
		let src = 'try {} catch (e) {}\nlet z = 1;\n';
		let scope = scopeAt(src, 'let z');
		assert.match(null, scopeGet(scope, 'e'));
	});
});

// ── scopeAtOffset binary search ───────────────────────────────────────────────

describe('scopeAtOffset', () => {
	it('returns first scope for offset before any checkpoint', () => {
		let src = 'let x = 1;\n';
		let tree = parse(src);
		let map  = buildScopeMap(URI, src, tree);
		// offset 0 is before any declaration — scope should be the import/builtin scope.
		let scope = scopeAtOffset(map, 0);
		// 'length' is always in the builtin scope.
		assert.match('function', scopeGet(scope, 'length')?.kind);
	});

	it('returns last scope for offset past end', () => {
		let src = 'let x = 1;\nlet y = 2;\n';
		let tree = parse(src);
		let map  = buildScopeMap(URI, src, tree);
		let scope = scopeAtOffset(map, length(src) + 100);
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'x'));
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'y'));
	});
});

// ── template mode: declarations inside {% %} tags (b1) ──────────────────────────

describe('buildScopeMap template mode', () => {
	it('a let declared in a statement tag is visible at a later expression tag', () => {
		let src = "{% let title = 'Home'; %}\n<h1>{{ title }}</h1>\n";
		let scope = scopeAtTpl(src, '{{ title');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'title'));
	});

	it('a declaration in one tag is visible in a later tag', () => {
		let src = "{% let count = 3; %}\n{% let next = count; %}\n";
		let scope = scopeAtTpl(src, 'let next');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'count'));
	});

	it('surfaces every declaration of a multi-statement tag', () => {
		let src = "{% let a = 1; let b = 2; %}\n{{ b }}\n";
		let scope = scopeAtTpl(src, '{{ b');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'a'));
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'b'));
	});

	it('an exported function in a tag is visible to a later tag', () => {
		let src = "{% export function render(x) { return x; }; %}\n{% let r = render; %}\n";
		let scope = scopeAtTpl(src, 'let r');
		assert.match('function', scopeGet(scope, 'render')?.kind);
	});
});

// ── template mode: spanning control-flow forms (b2) ─────────────────────────────

describe('buildScopeMap template spanning forms', () => {
	it('for-in loop variable is typed from the iterable inside the body', () => {
		let src = "{% for (item in ['a', 'b']): %}\n<li>{{ item }}</li>\n{% endfor %}\n";
		let scope = scopeAtTpl(src, '{{ item');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'item'));
	});

	it('for-in over a list of ints types the loop variable as int', () => {
		let src = "{% for (n in [1, 2, 3]): %}\n{{ n }}\n{% endfor %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('an outer tag declaration is visible inside the loop body', () => {
		let src = "{% let base = 10; %}\n{% for (n in [1]): %}\n{{ base }}\n{% endfor %}\n";
		let scope = scopeAtTpl(src, '{{ base');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'base'));
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('a C-style for initializer variable is visible in the body', () => {
		let src = "{% for (let i = 0; i < 3; i++): %}\n{{ i }}\n{% endfor %}\n";
		let scope = scopeAtTpl(src, '{{ i');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'i'));
	});

	it('a let declared inside the loop body threads to later body nodes', () => {
		let src = "{% for (n in [1]): %}\n{% let sq = n; %}\n{{ sq }}\n{% endfor %}\n";
		let scope = scopeAtTpl(src, '{{ sq');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'sq'));
	});

	it('an if-block body resolves outer declarations', () => {
		let src = "{% let flag = 1; %}\n{% if (flag): %}\n{{ flag }}\n{% endif %}\n";
		let scope = scopeAtTpl(src, '{{ flag');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'flag'));
	});

	it('the loop variable is not visible after the loop', () => {
		let src = "{% for (item in ['a']): %}\n{{ item }}\n{% endfor %}\n{% let after = 1; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		assert.match(null, scopeGet(scope, 'item'));
	});
});

// ── template mode: brace-spanning control-flow forms ({% for … { %}…{% } %}) ────
// The brace form spans tags with `{ … }` instead of `: … end…`; it parses to the
// ordinary for/while/if/try nodes, with the text between tags as text_statement
// nodes inside their statement_block.

describe('buildScopeMap template brace-spanning forms', () => {
	it('for-in loop variable is typed from the iterable inside the body', () => {
		let src = "{% for (n in [1, 2, 3]) { %}\n{{ n }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('a C-style for initializer variable is visible in the body', () => {
		let src = "{% for (let i = 0; i < 3; i++) { %}\n{{ i }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ i');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'i'));
	});

	it('an outer tag declaration is visible inside a while body', () => {
		let src = "{% let base = 10; %}\n{% while (base) { %}\n{{ base }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ base');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'base'));
	});

	it('a let declared inside the loop body threads to later body nodes', () => {
		let src = "{% for (n in [1]) { %}\n{% let sq = n; %}\n{{ sq }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ sq');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'sq'));
	});

	it('the loop variable is not visible after the loop', () => {
		let src = "{% for (item in ['a']) { %}\n{{ item }}\n{% } %}\n{% let after = 1; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		assert.match(null, scopeGet(scope, 'item'));
	});
});

// ── template mode: brace-spanning if/elif/else narrowing ────────────────────────
// {% if (c) { %}…{% } else if (c2) { %}…{% } else { %}…{% } %} parses to an
// ordinary if_statement with else_clause branches.

describe('buildScopeMap template brace-form if/elif/else narrowing', () => {
	const nullable = "{% let m = (1 > 0) ? 'str' : null; %}\n";

	it('the true branch narrows a nullable to non-null', () => {
		let src = nullable + "{% if (m) { %}\n{{ m }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ m');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'm'));
	});

	it('the else branch sees the if condition as false', () => {
		let src = nullable + "{% if (m) { %}\nt\n{% } else { %}\n{{ m }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ m');
		assert.match({ kind: 'primitive', name: 'null' }, scopeGet(scope, 'm'));
	});

	it('an else-if branch narrows on its own condition', () => {
		let src = "{% let a = (1 > 0) ? 'x' : null; %}\n" +
		          "{% let b = (1 > 0) ? 'y' : null; %}\n" +
		          "{% if (a) { %}\nt\n{% } else if (b) { %}\n{{ b }}\n{% } else { %}\nf\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ b');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'b'));
	});

	it('narrowing does not leak past the closing tag', () => {
		let src = nullable + "{% if (m) { %}\nt\n{% } %}\n{% let after = m; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		assert.match('union', scopeGet(scope, 'm')?.kind);
	});
});

// ── template mode: brace-spanning try/catch ({% try { %}…{% } catch (e) { %}) ────

describe('buildScopeMap template brace-spanning try/catch', () => {
	it('the catch parameter is visible as a string inside the catch body', () => {
		let src = "{% try { %}\nx\n{% } catch (e) { %}\n{{ e }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ e');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'e'));
	});

	it('an outer declaration is visible inside the try body', () => {
		let src = "{% let base = 10; %}\n{% try { %}\n{{ base }}\n{% } catch (e) { %}\nx\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ base');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'base'));
	});

	it('a let declared inside the try body threads to later body nodes', () => {
		let src = "{% try { %}\n{% let n = 5; %}\n{{ n }}\n{% } catch (e) { %}\nx\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('the catch parameter is not visible after the try', () => {
		let src = "{% try { %}\nx\n{% } catch (e) { %}\ny\n{% } %}\n{% let after = 1; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		assert.match(null, scopeGet(scope, 'e'));
	});
});

// ── template mode: spanning function forms ─────────────────────────────────────
// {% function f(a) { %}…{% } %} and the colon form {% function f(a): %}…
// {% endfunction %} — both ordinary function_declaration nodes (brace body, or a
// run of body statements), so params bind exactly as in a script.

describe('buildScopeMap template spanning function forms', () => {
	it('a brace-form parameter is visible inside the body', () => {
		let src = "{% function f(a, b) { %}\n{{ a }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ a');
		assert.match('unknown', scopeGet(scope, 'a')?.kind);
		assert.match('unknown', scopeGet(scope, 'b')?.kind);
	});

	it('a colon-form parameter is visible inside the body', () => {
		let src = "{% function g(a): %}\n{{ a }}\n{% endfunction %}\n";
		let scope = scopeAtTpl(src, '{{ a');
		assert.match('unknown', scopeGet(scope, 'a')?.kind);
	});

	it('an outer declaration is visible inside the function body', () => {
		let src = "{% let base = 10; %}\n{% function f(a) { %}\n{{ base }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ base');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'base'));
	});

	it('a let declared inside the body threads to later body nodes', () => {
		let src = "{% function f(a) { %}\n{% let n = 5; %}\n{{ n }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('a parameter is not visible after the function', () => {
		let src = "{% function f(a) { %}\nx\n{% } %}\n{% let after = 1; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		assert.match(null, scopeGet(scope, 'a'));
	});
});

// ── template mode: if/elif/else branch narrowing (flat alt form) ────────────────

describe('buildScopeMap template if/elif/else narrowing', () => {
	// The ternary gives `m` the union type string|null so the guards have
	// something to narrow; a plain literal would already be non-null.
	const nullable = "{% let m = (1 > 0) ? 'str' : null; %}\n";

	it('the true branch narrows a nullable to non-null', () => {
		let src = nullable + "{% if (m): %}\n{{ m }}\n{% endif %}\n";
		let scope = scopeAtTpl(src, '{{ m');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'm'));
	});

	it('the else branch sees the if condition as false', () => {
		let src = nullable + "{% if (m): %}\nt\n{% else %}\n{{ m }}\n{% endif %}\n";
		let scope = scopeAtTpl(src, '{{ m');
		assert.match({ kind: 'primitive', name: 'null' }, scopeGet(scope, 'm'));
	});

	it('an elif branch narrows on its own condition', () => {
		let src = "{% let a = (1 > 0) ? 'x' : null; %}\n" +
		          "{% let b = (1 > 0) ? 'y' : null; %}\n" +
		          "{% if (a): %}\nt\n{% elif (b): %}\n{{ b }}\n{% else %}\nf\n{% endif %}\n";
		let scope = scopeAtTpl(src, '{{ b');
		assert.match({ kind: 'primitive', name: 'string' }, scopeGet(scope, 'b'));
	});

	it('narrowing does not leak past endif', () => {
		let src = nullable + "{% if (m): %}\nt\n{% endif %}\n{% let after = m; %}\n";
		let scope = scopeAtTpl(src, 'let after');
		// After the if, m is back to its declared union (string|null), not the
		// non-null narrowing the true branch saw.
		assert.match('union', scopeGet(scope, 'm')?.kind);
	});

	it('an outer declaration is visible inside a narrowed branch', () => {
		let src = nullable + "{% let n = 5; %}\n{% if (m): %}\n{{ n }}\n{% endif %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});
});

// ---------------------------------------------------------------------------
// Property-based tests over a run of top-level `let` declarations:
//   * declared-before-visible — a name is invisible at every offset before its
//     own statement and visible from that statement's checkpoint onward;
//   * monotonicity — the set of visible names only grows as the offset advances
//     (no block scopes / shadowing here, so nothing ever leaves scope).
// ---------------------------------------------------------------------------

// Distinct two-letter names, so index() locates each declaration unambiguously.
let NAMES = ['aa', 'bb', 'cc', 'dd', 'ee', 'ff', 'gg', 'hh'];

// "let aa = 1;\nlet bb = 1;\n…" for the first n names.
function letChain(n) {
	let src = '';
	for (let i = 0; i < n; i++)
		src += 'let ' + NAMES[i] + ' = 1;\n';
	return src;
}

// How many of the first n names are visible in `scope`.
function visibleCount(scope, n) {
	let c = 0;
	for (let i = 0; i < n; i++)
		if (scopeGet(scope, NAMES[i]) !== null) c++;
	return c;
}

describe('scopeAtOffset — properties', () => {
	prop('a let binding is visible from its own statement onward, never before',
		gen.int(1, length(NAMES)),
		(n, ctx) => {
			ctx.classify('single', n === 1);
			let src = letChain(n);
			let map = buildScopeMap(URI, src, parse(src));

			// Nothing is declared at the very start of the file.
			let at0 = scopeAtOffset(map, 0);
			for (let i = 0; i < n; i++)
				assert.match(null, scopeGet(at0, NAMES[i]),
					sprintf('%s leaked before any declaration', NAMES[i]));

			// At statement k's checkpoint, names 0..k-1 are in scope, k..n-1 are not.
			for (let k = 0; k < n; k++) {
				let sc = scopeAtOffset(map, index(src, 'let ' + NAMES[k]));
				for (let i = 0; i < k; i++)
					assert.match(true, scopeGet(sc, NAMES[i]) !== null,
						sprintf('%s should be visible at statement %d', NAMES[i], k));
				for (let i = k; i < n; i++)
					assert.match(null, scopeGet(sc, NAMES[i]),
						sprintf('%s visible before its own declaration', NAMES[i]));
			}
		});

	prop('visible-name count is monotonic non-decreasing as the offset advances',
		gen.int(1, length(NAMES)),
		(n) => {
			let src = letChain(n);
			let map = buildScopeMap(URI, src, parse(src));

			// Probe every statement start plus end-of-file, in increasing order.
			let offsets = [0];
			for (let k = 0; k < n; k++) push(offsets, index(src, 'let ' + NAMES[k]));
			push(offsets, length(src));

			let prev = -1;
			for (let off in offsets) {
				let cur = visibleCount(scopeAtOffset(map, off), n);
				assert.match(true, cur >= prev,
					sprintf('visible count dropped from %d to %d at offset %d', prev, cur, off));
				prev = cur;
			}
			// By end of file all n names are in scope.
			assert.match(n, visibleCount(scopeAtOffset(map, length(src)), n));
		});
});

// ── template mode: shapes the statement-stream grammar newly parses ─────────────
// Before the markup grammar modelled a template as ucode's statement stream these
// were ERROR trees (only an enumerated set of shapes could span tags).

describe('buildScopeMap template statement-stream shapes', () => {
	it('an arrow function body spanning tags binds its parameter', () => {
		let src = "{% let show = (item) => { %}\n{{ item }}\n{% }; %}\n";
		let scope = scopeAtTpl(src, '{{ item');
		assert.match('unknown', scopeGet(scope, 'item')?.kind);
	});

	it('a switch case body spanning tags sees outer declarations', () => {
		let src = "{% let base = 10; %}\n{% switch (base) { case 10: %}\n{{ base }}\n{% break; } %}\n";
		let scope = scopeAtTpl(src, '{{ base');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'base'));
	});

	it('a statement sharing the tag before a block header is visible in the block', () => {
		let src = "{% let n = 5; if (n) { %}\n{{ n }}\n{% } %}\n";
		let scope = scopeAtTpl(src, '{{ n');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'n'));
	});

	it('a let inside a colon-form function body threads to later body nodes', () => {
		let src = "{% function f(a): %}\n{% let k = 3; %}\n{{ k }}\n{% endfunction %}\n";
		let scope = scopeAtTpl(src, '{{ k');
		assert.match({ kind: 'primitive', name: 'int' }, scopeGet(scope, 'k'));
	});
});
