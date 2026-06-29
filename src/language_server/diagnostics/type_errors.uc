import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';
import { makeScope, scopeGet, scopeSet } from 'language_server.types.scope';
import { UNKNOWN, NULL_T } from 'language_server.types.type_utils';
import { importScope, inferNode, processDecl } from 'language_server.types.inferrer';

let SEVERITY_ERROR   = 1;
let SEVERITY_WARNING = 2;

// ── Type predicates ───────────────────────────────────────────────────────────

function isCallable(type) {
	if (!type || type.kind === 'unknown') return true;
	if (type.kind === 'function') return true;
	if (type.kind === 'nullable') return isCallable(type.inner);
	if (type.kind === 'union') {
		for (let i = 0; i < length(type.members); i++)
			if (isCallable(type.members[i])) return true;
		return false;
	}
	return false;
}

function isNullLike(type) {
	if (!type) return false;
	if (type.kind === 'primitive' && type.name === 'null') return true;
	if (type.kind === 'nullable') return true;
	if (type.kind === 'union') {
		for (let i = 0; i < length(type.members); i++)
			if (isNullLike(type.members[i])) return true;
		return false;
	}
	return false;
}

// Returns the field name that is missing on a known record type, or null if
// the field exists or the type is not a concrete record.
function unknownFieldOf(type, propName) {
	if (!type || type.kind === 'unknown') return null;
	if (type.kind === 'nullable') return unknownFieldOf(type.inner, propName);
	if (type.kind !== 'record') return null;
	let fields = type.fields ?? [];
	for (let i = 0; i < length(fields); i++)
		if (fields[i].name === propName) return null;
	return propName;
}

// ── Guard parsing and narrowing ───────────────────────────────────────────────

// Parse an AST condition into { name, positive } where positive=true means
// "name is non-null/truthy in the branch where this guard holds".
//   x          → { name: 'x', positive: true }
//   !x         → { name: 'x', positive: false }
//   x !== null → { name: 'x', positive: true }   (also x != null, null !== x, etc.)
function parseGuard(node, source) {
	if (!node) return null;
	let nt = ts.nodeType(node);

	// The condition field of if_statement is wrapped in parentheses.
	if (nt === 'parenthesized_expression')
		return parseGuard(ts.namedChild(node, 0), source);

	if (nt === 'identifier')
		return { name: ts.text(node, source), positive: true };

	if (nt === 'unary_expression') {
		if (ts.nodeType(ts.child(node, 0)) === '!') {
			let operand = ts.namedChild(node, 0);
			if (operand && ts.nodeType(operand) === 'identifier')
				return { name: ts.text(operand, source), positive: false };
		}
		return null;
	}

	if (nt === 'binary_expression') {
		let op = ts.nodeType(ts.child(node, 1));
		if (op !== '!==' && op !== '!=') return null;
		let left  = ts.namedChild(node, 0);
		let right = ts.namedChild(node, 1);
		if (!left || !right) return null;
		if (ts.nodeType(right) === 'null' && ts.nodeType(left) === 'identifier')
			return { name: ts.text(left, source), positive: true };
		if (ts.nodeType(left) === 'null' && ts.nodeType(right) === 'identifier')
			return { name: ts.text(right, source), positive: true };
	}

	return null;
}

function narrowToNonNull(type) {
	if (!type || type.kind === 'unknown') return UNKNOWN;
	if (type.kind === 'nullable') return type.inner;
	if (type.kind === 'primitive' && type.name === 'null') return UNKNOWN;
	if (type.kind === 'union') {
		let kept = [];
		for (let i = 0; i < length(type.members); i++) {
			let m = type.members[i];
			if (!(m.kind === 'primitive' && m.name === 'null')) push(kept, m);
		}
		if (length(kept) === 0) return UNKNOWN;
		if (length(kept) === 1) return kept[0];
		return { kind: 'union', members: kept };
	}
	return type;
}

// Apply a guard narrowing to scope.
//   positive=true  → entering the branch where the guard holds (e.g., if-body)
//   positive=false → entering the branch where the guard does NOT hold (e.g., else,
//                    or subsequent siblings after a guard-clause terminator)
function applyGuard(scope, guard, positive) {
	if (!guard) return;
	let current = scopeGet(scope, guard.name);
	let inTrueBranch = guard.positive ? positive : !positive;
	let narrowed;
	if (inTrueBranch) {
		narrowed = narrowToNonNull(current ?? UNKNOWN);
	} else {
		narrowed = NULL_T;
	}
	scopeSet(scope, guard.name, narrowed);
}

// True when a node unconditionally transfers control away from the current
// block (return, break, continue, throw).
function endsInTerminator(node) {
	if (!node) return false;
	let nt = ts.nodeType(node);
	if (nt === 'return_statement' || nt === 'break_statement' ||
	    nt === 'continue_statement' || nt === 'throw_statement') return true;
	if (nt === 'statement_block') {
		let n = ts.namedChildCount(node);
		return n > 0 && endsInTerminator(ts.namedChild(node, n - 1));
	}
	return false;
}

// ── Core walk ─────────────────────────────────────────────────────────────────

let _walk;
let _walkBlock;

// Walk a statement_block (or program root) statement-by-statement so that
// guard-clause narrowings accumulate for subsequent siblings.
_walkBlock = function(node, scope, source, uri, lineTable, diags) {
	let n = ts.namedChildCount(node);
	for (let i = 0; i < n; i++) {
		let stmt = ts.namedChild(node, i);
		let nt = ts.nodeType(stmt);

		if (nt === 'if_statement') {
			let cond = ts.childByField(stmt, 'condition');
			let cons = ts.childByField(stmt, 'consequence');
			let alt  = ts.childByField(stmt, 'alternative');
			let guard = parseGuard(cond, source);

			// Check the condition itself for type errors.
			if (cond) _walk(cond, scope, source, uri, lineTable, diags);

			// Walk the consequent with the narrowed (positive) scope.
			if (cons) {
				let thenScope = makeScope(scope);
				applyGuard(thenScope, guard, true);
				_walk(cons, thenScope, source, uri, lineTable, diags);
			}

			// Walk the alternative with the negated (negative) scope.
			if (alt) {
				let elseScope = makeScope(scope);
				applyGuard(elseScope, guard, false);
				_walk(alt, elseScope, source, uri, lineTable, diags);
			}

			// Guard clause: no else branch, consequence terminates →
			// narrow the current scope for all subsequent siblings.
			if (!alt && guard && endsInTerminator(cons))
				applyGuard(scope, guard, false);

		} else {
			_walk(stmt, scope, source, uri, lineTable, diags);
		}
	}
};

_walk = function(node, scope, source, uri, lineTable, diags) {
	if (!node) return;
	let nt = ts.nodeType(node);

	// ── Declarations: extend scope, walk initialiser values ──────────────────

	if (nt === 'lexical_declaration') {
		processDecl(node, source, uri, scope, 0);
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let decl = ts.namedChild(node, i);
			if (ts.nodeType(decl) !== 'variable_declarator') continue;
			let val = ts.childByField(decl, 'value');
			if (val) _walk(val, scope, source, uri, lineTable, diags);
		}
		return;
	}

	if (nt === 'function_declaration') {
		let fnType = inferNode(node, source, uri, scope, 0);
		let nameNode = ts.namedChild(node, 0);
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			scopeSet(scope, ts.text(nameNode, source), fnType);
		let inner = makeScope(scope);
		if (fnType && fnType.kind === 'function') {
			for (let i = 0; i < length(fnType.params); i++) {
				let p = fnType.params[i];
				scopeSet(inner, p.name, p.type ?? UNKNOWN);
			}
		}
		let body = ts.childByField(node, 'body');
		if (body) _walkBlock(body, inner, source, uri, lineTable, diags);
		return;
	}

	if (nt === 'export_statement') {
		let inner = ts.namedChild(node, 0);
		if (inner) _walk(inner, scope, source, uri, lineTable, diags);
		return;
	}

	if (nt === 'arrow_function' || nt === 'function_expression') {
		let inner = makeScope(scope);
		let fnType = inferNode(node, source, uri, scope, 0);
		if (fnType && fnType.kind === 'function') {
			for (let i = 0; i < length(fnType.params); i++) {
				let p = fnType.params[i];
				scopeSet(inner, p.name, p.type ?? UNKNOWN);
			}
		}
		let body = ts.childByField(node, 'body');
		if (body) {
			if (ts.nodeType(body) === 'statement_block')
				_walkBlock(body, inner, source, uri, lineTable, diags);
			else
				_walk(body, inner, source, uri, lineTable, diags);
		}
		return;
	}

	// ── Type error checks ─────────────────────────────────────────────────────

	if (nt === 'call_expression') {
		let callee = ts.childByField(node, 'function');
		if (callee) {
			if (ts.nodeType(callee) === 'identifier') {
				let calleeType = scopeGet(scope, ts.text(callee, source)) ?? UNKNOWN;
				if (!isCallable(calleeType)) {
					push(diags, {
						range:    rangeOf(source, lineTable, callee),
						severity: SEVERITY_ERROR,
						source:   'ucode-ls',
						code:     'not-a-function',
						message:  sprintf("'%s' is not a function (type: %s)", ts.text(callee, source), calleeType.kind),
					});
				}
			} else {
				_walk(callee, scope, source, uri, lineTable, diags);
			}
		}
		let args = ts.childByField(node, 'arguments');
		if (args) {
			for (let i = 0; i < ts.namedChildCount(args); i++)
				_walk(ts.namedChild(args, i), scope, source, uri, lineTable, diags);
		}
		return;
	}

	if (nt === 'member_expression') {
		let obj  = ts.childByField(node, 'object');
		let prop = ts.childByField(node, 'property');
		if (obj) {
			let objType = ts.nodeType(obj) === 'identifier'
				? (scopeGet(scope, ts.text(obj, source)) ?? UNKNOWN)
				: inferNode(obj, source, uri, scope, 0);
			if (isNullLike(objType)) {
				push(diags, {
					range:    rangeOf(source, lineTable, obj),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'may-be-null',
					message:  sprintf("'%s' may be null", ts.text(obj, source)),
				});
			} else if (prop && ts.nodeType(prop) === 'property_identifier') {
				let field = unknownFieldOf(objType, ts.text(prop, source));
				if (field !== null) {
					push(diags, {
						range:    rangeOf(source, lineTable, prop),
						severity: SEVERITY_WARNING,
						source:   'ucode-ls',
						code:     'unknown-property',
						message:  sprintf("Property '%s' does not exist on this type", field),
					});
				}
			}
			// Recurse into the object to catch errors nested within it.
			if (ts.nodeType(obj) !== 'identifier') _walk(obj, scope, source, uri, lineTable, diags);
		}
		return;
	}

	// ── `&&` short-circuit: narrow RHS using the LHS guard ───────────────────

	if (nt === 'binary_expression') {
		let op = ts.nodeType(ts.child(node, 1));
		if (op === '&&') {
			let left  = ts.namedChild(node, 0);
			let right = ts.namedChild(node, 1);
			_walk(left, scope, source, uri, lineTable, diags);
			let guard = parseGuard(left, source);
			if (guard) {
				let rightScope = makeScope(scope);
				applyGuard(rightScope, guard, true);
				_walk(right, rightScope, source, uri, lineTable, diags);
			} else {
				_walk(right, scope, source, uri, lineTable, diags);
			}
			return;
		}
	}

	// ── Blocks: create child scope ────────────────────────────────────────────

	if (nt === 'statement_block')
		return _walkBlock(node, makeScope(scope), source, uri, lineTable, diags);

	// Skip import statements — no type errors to check inside.
	if (nt === 'import_statement') return;

	// ── Default: recurse through named children ───────────────────────────────

	let n = ts.namedChildCount(node);
	for (let i = 0; i < n; i++)
		_walk(ts.namedChild(node, i), scope, source, uri, lineTable, diags);
};

export function typeErrors(uri, doc) {
	let lineTable = buildLineTable(doc.text);
	let scope = importScope(uri);
	let diags = [];
	_walkBlock(ts.rootNode(doc.tree), scope, doc.text, uri, lineTable, diags);
	return diags;
};
