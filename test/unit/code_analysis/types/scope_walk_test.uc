import { describe, it, assert, beforeEach } from 'utest';
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

	it('compound && guard narrows in body', () => {
		let src = '/** @param {string|null} m */\nfunction f(m) {\n  if (m && type(m) === "string") {\n    let x = m;\n  }\n}\n';
		let scope = scopeAt(src, 'let x');
		let mType = scopeGet(scope, 'm');
		// The truthy sub-guard in the && narrows m to non-null string.
		assert.match({ kind: 'primitive', name: 'string' }, mType);
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
		let src = "{% export function render(x) { return x; } %}\n{% let r = render; %}\n";
		let scope = scopeAtTpl(src, 'let r');
		assert.match('function', scopeGet(scope, 'render')?.kind);
	});
});
