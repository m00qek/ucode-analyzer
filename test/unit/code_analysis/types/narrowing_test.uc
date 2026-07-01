import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import { narrowToNonNull, parseGuard, applyGuard } from 'code_analysis.types.narrowing';
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
