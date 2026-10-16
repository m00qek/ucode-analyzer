import { describe, it, assert, prop, gen } from 'utest';
import * as ts from 'tree_sitter';
import { narrowToNonNull, parseGuard, applyGuard, narrowUnionByDiscriminant } from 'code_analysis.types.narrowing';
import { makeScope, scopeGet, scopeSet } from 'code_analysis.types.scope';
import { UNKNOWN, NULL_T, STR, INT, FLOAT, BOOL } from 'code_analysis.types.type_utils';

let NULLABLE_STR = { kind: 'nullable', inner: STR };
let UNION_STR_NULL = { kind: 'union', members: [STR, NULL_T] };

// ── narrowToNonNull ───────────────────────────────────────────────────────────

describe('narrowToNonNull', () => {
	it('returns UNKNOWN for unknown input', () => {
		assert.match(UNKNOWN, narrowToNonNull(UNKNOWN));
	});

	it('returns UNKNOWN for null input', () => {
		assert.match(UNKNOWN, narrowToNonNull(null));
	});

	it('unwraps nullable', () => {
		assert.match(STR, narrowToNonNull(NULLABLE_STR));
	});

	it('returns UNKNOWN for bare null type', () => {
		assert.match(UNKNOWN, narrowToNonNull(NULL_T));
	});

	it('strips null from union, returning single member', () => {
		assert.match(STR, narrowToNonNull(UNION_STR_NULL));
	});

	it('strips null from multi-member union, keeping rest', () => {
		let u = { kind: 'union', members: [STR, INT, NULL_T] };
		let result = narrowToNonNull(u);
		assert.match('union', result.kind);
		assert.match(2, length(result.members));
	});

	it('unwraps a nullable member of a union (`c ? match(…) : null`)', () => {
		assert.match(STR, narrowToNonNull({ kind: 'union', members: [NULLABLE_STR, NULL_T] }));
	});

	it('passes through a non-null type unchanged', () => {
		assert.match(STR, narrowToNonNull(STR));
	});
});

// ── parseGuard ────────────────────────────────────────────────────────────────

let _parser = ts.newParser(ts.ucode());

function parseSource(src) {
	return { tree: ts.parse(_parser, src), source: src };
}

function conditionNode(doc) {
	// if_statement > parenthesized_expression > condition
	let root = ts.rootNode(doc.tree);
	let stmt = ts.namedChild(root, 0);
	return ts.childByField(stmt, 'condition');
}

describe('parseGuard', () => {
	it('identifier → positive guard', () => {
		let doc = parseSource('if (x) {}');
		let cond = conditionNode(doc);
		// cond is parenthesized_expression; parseGuard unwraps it
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
	});

	it('!x → negative guard', () => {
		let doc = parseSource('if (!x) {}');
		let cond = conditionNode(doc);
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(false, g.positive);
	});

	it('x !== null → positive guard', () => {
		let doc = parseSource('if (x !== null) {}');
		let cond = conditionNode(doc);
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
	});

	it('x != null → positive guard', () => {
		let doc = parseSource('if (x != null) {}');
		let cond = conditionNode(doc);
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
	});

	it('x === null → negative guard', () => {
		let doc = parseSource('if (x === null) {}');
		let cond = conditionNode(doc);
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(false, g.positive);
	});

	it('null !== x → positive guard (operands reversed)', () => {
		let doc = parseSource('if (null !== x) {}');
		let cond = conditionNode(doc);
		let g = parseGuard(cond, doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
	});

	it('unrecognised expression → null', () => {
		let doc = parseSource('if (a + b) {}');
		let cond = conditionNode(doc);
		assert.match(null, parseGuard(cond, doc.source));
	});

	it('type(x) === "string" → positive guard with toType STR', () => {
		let doc = parseSource('if (type(x) === "string") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
		assert.match(STR, g.toType);
	});

	it('type(x) !== "string" → negative guard with toType STR', () => {
		let doc = parseSource('if (type(x) !== "string") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('x', g.name);
		assert.match(false, g.positive);
		assert.match(STR, g.toType);
	});

	it('"int" === type(x) → positive guard (operands reversed)', () => {
		let doc = parseSource('if ("int" === type(x)) {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('x', g.name);
		assert.match(true, g.positive);
		assert.match(INT, g.toType);
	});

	it('r.kind === "fail" → positive variant guard', () => {
		let g = parseGuard(conditionNode(parseSource('if (r.kind === "fail") {}')), 'if (r.kind === "fail") {}');
		assert.match('variant', g.kind);
		assert.match('r', g.name);
		assert.match('kind', g.field);
		assert.match('fail', g.value);
		assert.match(true, g.positive);
	});

	it('r.kind !== "fail" → negative variant guard', () => {
		let doc = parseSource('if (r.kind !== "fail") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('variant', g.kind);
		assert.match(false, g.positive);
	});

	it('"fail" === r.kind → variant guard (operands reversed)', () => {
		let doc = parseSource('if ("fail" === r.kind) {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('variant', g.kind);
		assert.match('r', g.name);
		assert.match('fail', g.value);
	});

	it('r.tag === 2 → variant guard with a numeric discriminant', () => {
		let doc = parseSource('if (r.tag === 2) {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('variant', g.kind);
		assert.match('tag', g.field);
		assert.match(2, g.value);
	});

	it('type(x) === "bool" → toType BOOL', () => {
		let doc = parseSource('if (type(x) === "bool") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match(BOOL, g.toType);
	});

	it('type(x) === "double" → toType FLOAT', () => {
		let doc = parseSource('if (type(x) === "double") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match(FLOAT, g.toType);
	});

	it('type(x) === "array" → non-null guard for the true branch (no array singleton)', () => {
		// No singleton type for array, but type(x)==='array' still proves x is
		// non-null; an 'and'-wrapped truthy guard narrows only the true branch.
		let doc = parseSource('if (type(x) === "array") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match('and', g.kind);
		assert.match('truthy', g.guards[0].kind);
		assert.match('x', g.guards[0].name);
		assert.match(true, g.guards[0].positive);
	});

	it('type(x) !== "array" → null (cannot narrow the unmapped negative case)', () => {
		let doc = parseSource('if (type(x) !== "array") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match(null, g);
	});

	it('type(x, extra) === "string" → null (only single-arg calls qualify)', () => {
		let doc = parseSource('if (type(x, y) === "string") {}');
		let g = parseGuard(conditionNode(doc), doc.source);
		assert.match(null, g);
	});
});

// ── applyGuard (typeof) ───────────────────────────────────────────────────────

describe('applyGuard type() narrowing', () => {
	it('positive typeof guard narrows to toType', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', UNKNOWN);
		applyGuard(scope, { kind: 'type', name: 'x', positive: true, toType: STR }, true);
		assert.match(STR, scopeGet(scope, 'x'));
	});

	it('positive typeof guard in alternate branch leaves union minus that type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'union', members: [STR, INT, NULL_T] });
		applyGuard(scope, { kind: 'type', name: 'x', positive: true, toType: STR }, false);
		let t = scopeGet(scope, 'x');
		assert.match('union', t.kind);
		assert.match(2, length(t.members));
	});

	it('negative typeof guard in true branch filters type from union', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'union', members: [STR, INT] });
		applyGuard(scope, { kind: 'type', name: 'x', positive: false, toType: STR }, true);
		assert.match(INT, scopeGet(scope, 'x'));
	});

	it('negative typeof guard in false branch narrows to toType', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', { kind: 'union', members: [STR, INT] });
		applyGuard(scope, { kind: 'type', name: 'x', positive: false, toType: STR }, false);
		assert.match(STR, scopeGet(scope, 'x'));
	});

	it('typeof guard on non-union in alternate branch leaves type unchanged', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', UNKNOWN);
		applyGuard(scope, { kind: 'type', name: 'x', positive: true, toType: STR }, false);
		assert.match(UNKNOWN, scopeGet(scope, 'x'));
	});
});

// ── applyGuard ────────────────────────────────────────────────────────────────

describe('applyGuard', () => {
	it('positive=true narrows nullable to inner type', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', NULLABLE_STR);
		applyGuard(scope, { kind: 'truthy', name: 'x', positive: true }, true);
		assert.match(STR, scopeGet(scope, 'x'));
	});

	it('positive=false sets to NULL_T for a positive guard', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', NULLABLE_STR);
		applyGuard(scope, { kind: 'truthy', name: 'x', positive: true }, false);
		assert.match(NULL_T, scopeGet(scope, 'x'));
	});

	it('negative guard: positive=true sets to NULL_T', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', NULLABLE_STR);
		applyGuard(scope, { kind: 'truthy', name: 'x', positive: false }, true);
		assert.match(NULL_T, scopeGet(scope, 'x'));
	});

	it('negative guard: positive=false narrows to non-null', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', NULLABLE_STR);
		applyGuard(scope, { kind: 'truthy', name: 'x', positive: false }, false);
		assert.match(STR, scopeGet(scope, 'x'));
	});

	it('no-op when guard is null', () => {
		let scope = makeScope(null);
		scopeSet(scope, 'x', NULLABLE_STR);
		applyGuard(scope, null, true);
		assert.match(NULLABLE_STR, scopeGet(scope, 'x'));
	});
});

describe('narrowUnionByDiscriminant', () => {
	function litStr(v) { return { kind: 'primitive', name: 'string', value: v }; }
	let PASS = { kind: 'record', fields: [{ name: 'kind', type: litStr('pass') }] };
	let FAIL = { kind: 'record', fields: [
		{ name: 'kind',  type: litStr('fail') },
		{ name: 'value', type: INT },
	]};
	let U = { kind: 'union', members: [PASS, FAIL] };

	it('true branch keeps the matching variant', () => {
		assert.match(FAIL, narrowUnionByDiscriminant(U, 'kind', 'fail', true));
	});

	it('false branch drops the matching variant', () => {
		assert.match(PASS, narrowUnionByDiscriminant(U, 'kind', 'fail', false));
	});

	it('leaves a non-union type unchanged', () => {
		assert.match(STR, narrowUnionByDiscriminant(STR, 'kind', 'fail', true));
	});

	it('keeps a variant whose discriminant is unknown in both branches', () => {
		let OPEN = { kind: 'record', fields: [{ name: 'kind', type: STR }] };  // no literal value
		let u2 = { kind: 'union', members: [FAIL, OPEN] };
		// true branch: FAIL matches, OPEN unknown → both survive
		assert.match('union', narrowUnionByDiscriminant(u2, 'kind', 'fail', true).kind);
		// false branch: FAIL dropped, OPEN survives → single member
		assert.match(OPEN, narrowUnionByDiscriminant(u2, 'kind', 'fail', false));
	});

	it('returns the union unchanged when nothing matches', () => {
		assert.match(U, narrowUnionByDiscriminant(U, 'kind', 'other', true));
	});
});

// ---------------------------------------------------------------------------
// Property: narrowToNonNull is *sound* (its result never admits null — no bare
// null primitive, no nullable wrapper, no null member left in a union) and
// *idempotent* (narrowing an already-narrowed type changes nothing). These are
// the two contracts every caller relies on when it drops a guard's null case.
// ---------------------------------------------------------------------------

let ALL_T     = [STR, INT, FLOAT, BOOL, NULL_T];
let NONNULL_T = [STR, INT, FLOAT, BOOL];

// True when no null can flow through `t` at the top level.
function isNullFree(t) {
	if (t.kind === 'nullable') return false;
	if (t.kind === 'primitive' && t.name === 'null') return false;
	if (t.kind === 'union')
		for (let m in t.members)
			if (m.kind === 'primitive' && m.name === 'null') return false;
	return true;
}

function buildType(c) {
	if (c.mode === 'unknown')  return UNKNOWN;
	if (c.mode === 'bare')     return ALL_T[c.idxs[0]];
	if (c.mode === 'nullable') return { kind: 'nullable', inner: NONNULL_T[c.innerIdx] };
	let members = [];
	for (let ix in c.idxs) push(members, ALL_T[ix]);   // ix is a value (an index into ALL_T)
	return { kind: 'union', members };
}

describe('narrowToNonNull — properties', () => {
	let typeGen = gen.record({
		mode:     gen.elements('bare', 'nullable', 'union', 'unknown'),
		idxs:     gen.array(gen.int(0, length(ALL_T) - 1), { min_len: 1, max_len: 4 }),
		innerIdx: gen.int(0, length(NONNULL_T) - 1),
	});

	prop('the result is null-free (sound)',
		typeGen,
		(c, ctx) => {
			let t = buildType(c);
			ctx.classify('nullable-in',  t.kind === 'nullable');
			ctx.classify('union-in',     t.kind === 'union');
			assert.match(true, isNullFree(narrowToNonNull(t)),
				sprintf('narrowToNonNull left a null in %J', narrowToNonNull(t)));
		});

	prop('narrowing is idempotent',
		typeGen,
		(c) => {
			let once  = narrowToNonNull(buildType(c));
			let twice = narrowToNonNull(once);
			assert.match(once, twice);
		});
});
