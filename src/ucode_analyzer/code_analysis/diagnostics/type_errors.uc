import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { scopeGet } from 'ucode_analyzer.code_analysis.types.scope';
import { UNKNOWN, resolveRef } from 'ucode_analyzer.code_analysis.types.type_utils';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { stringLiteralText, isComment, firstNamed } from 'ucode_analyzer.code_analysis.ast_text';

let SEVERITY_ERROR   = 1;
let SEVERITY_WARNING = 2;

function isNonIterable(type) {
	if (!type || type.kind === 'unknown') return false;
	if (type.kind === 'nullable') return isNonIterable(type.inner);
	if (type.kind === 'primitive')
		return type.name === 'int' || type.name === 'float' ||
		       type.name === 'boolean' || type.name === 'null';
	if (type.kind === 'function') return true;
	return false;
}

function isCallable(type) {
	if (!type || type.kind === 'unknown') return true;
	type = resolveRef(type);
	// An unresolved (or cyclic) typedef ref is treated as "assume OK" rather
	// than flagged, matching how unknown types are handled.
	if (type.kind === 'unknown' || type.kind === 'ref') return true;
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
	type = resolveRef(type);
	if (type.kind === 'primitive' && type.name === 'null') return true;
	if (type.kind === 'nullable') return true;
	if (type.kind === 'union') {
		for (let i = 0; i < length(type.members); i++)
			if (isNullLike(type.members[i])) return true;
		return false;
	}
	return false;
}

// Provably null: the type can *only* be null — a bare null primitive, or a
// union whose every member is itself provably null. A nullable (`T | null`) is
// deliberately excluded: it still has a non-null inhabitant, so dereferencing
// it is a *possible*, not a *certain*, error.
function isDefinitelyNull(type) {
	if (!type) return false;
	type = resolveRef(type);
	if (type.kind === 'primitive' && type.name === 'null') return true;
	if (type.kind === 'union') {
		if (length(type.members) === 0) return false;
		for (let i = 0; i < length(type.members); i++)
			if (!isDefinitelyNull(type.members[i])) return false;
		return true;
	}
	return false;
}

// A leading `'use strict';` directive puts the whole file in strict mode, where
// a *possibly*-null dereference is escalated from a warning to an error. Scan
// the directive prologue: the run of leading bare-string expression statements.
function isStrict(root, source) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (isComment(stmt)) continue;
		if (ts.nodeType(stmt) !== 'expression_statement') return false;
		let inner = firstNamed(stmt);
		if (!inner || ts.nodeType(inner) !== 'string') return false;
		if (stringLiteralText(inner, source) === 'use strict') return true;
		// another leading string directive — keep scanning the prologue
	}
	return false;
}

// True when this member_expression is the left-hand side of an assignment, i.e.
// a write target. ucode dicts are open, so `obj.newKey = ...` legitimately
// creates a property and must not be reported as unknown-property.
function isAssignmentTarget(node) {
	let parent = ts.parent(node);
	if (!parent) return false;
	let pt = ts.nodeType(parent);
	if (pt !== 'assignment_expression' && pt !== 'augmented_assignment_expression')
		return false;
	let left = ts.childByField(parent, 'left');
	return left && ts.startByte(left) === ts.startByte(node)
	            && ts.endByte(left) === ts.endByte(node);
}

// True when this member_expression is the operand of `delete`. Deleting a key
// that may not exist is a legal no-op in ucode, so it must not be reported as
// unknown-property (mirrors the assignment-target exemption above). `delete o.k`
// parses as a dedicated delete_expression node (its argument is always a
// member/subscript expression).
function isDeleteTarget(node) {
	let parent = ts.parent(node);
	return parent && ts.nodeType(parent) === 'delete_expression';
}

// `x.p` member writes (`x.p = …`, `x.p ??= …`) in the file, as "x.p" keys.
// ucode objects are open: after a write, `x.p` exists, so reading it is not
// an unknown property. Matched by name, not scope: that can only hide a
// finding, never add one.
let WRITES = `[
	(assignment_expression left: (member_expression object: (identifier) @obj property: (property_identifier) @prop))
	(augmented_assignment_expression left: (member_expression object: (identifier) @obj property: (property_identifier) @prop))
]`;
let _writeQuery = {};
let _written = {};

function writtenMembers(root, source) {
	let lang = ts.nodeType(root) === 'markup' ? 'markup' : 'ucode';
	_writeQuery[lang] ??= ts.newQuery(lang === 'markup' ? ts.markup() : ts.ucode(), WRITES);
	let out = {};
	for (let m in ts.queryMatches(_writeQuery[lang], root, source)) {
		let c = {};
		for (let cap in m.captures) c[cap.name] = cap.node;
		out[ts.text(c.obj, source) + '.' + ts.text(c.prop, source)] = true;
	}
	return out;
}

// Returns the field name that is missing on a known record type, or null if
// the field exists or the type is not a concrete record.
function unknownFieldOf(type, propName) {
	if (!type || type.kind === 'unknown') return null;
	type = resolveRef(type);
	if (type.kind === 'nullable') return unknownFieldOf(type.inner, propName);
	// For a union (e.g. an un-narrowed tagged union), report a field only when it
	// is definitely missing from every member: if any member could carry it —
	// present, open, empty, or non-record — the access stays silent. This mirrors
	// how a single record is checked, so unions aren't silently exempt.
	if (type.kind === 'union') {
		for (let i = 0; i < length(type.members); i++)
			if (unknownFieldOf(type.members[i], propName) === null) return null;
		return propName;
	}
	if (type.kind !== 'record') return null;
	// Open records (built from a spread of a non-record) have unknowable extra
	// keys; an empty record carries no field info at all. In both cases we can't
	// prove a property is missing, so treat them as dynamic dicts.
	if (type.open) return null;
	let fields = type.fields ?? [];
	if (length(fields) === 0) return null;
	for (let i = 0; i < length(fields); i++)
		if (fields[i].name === propName) return null;
	return propName;
}

// Report dereferencing `obj` (`obj.p` or `obj[i]`) when its type is null or
// may be null; `?.` is the null-safe form. Returns whether it reported.
function nullDiag(obj, objType, optChain, source, lineTable, diags, strict) {
	if (optChain) return false;
	if (isDefinitelyNull(objType)) {
		// The value can only ever be null — dereferencing it always fails.
		push(diags, {
			range:    rangeOf(source, lineTable, obj),
			severity: SEVERITY_ERROR,
			source:   'ucode-analyzer',
			code:     'null-access',
			message:  sprintf("'%s' is null", ts.text(obj, source)),
		});
		return true;
	}
	if (isNullLike(objType)) {
		// `T | null`: null is only one possibility, so this is a warning by
		// default. Under `'use strict';` it is escalated to an error.
		push(diags, {
			range:    rangeOf(source, lineTable, obj),
			severity: strict ? SEVERITY_ERROR : SEVERITY_WARNING,
			source:   'ucode-analyzer',
			code:     'may-be-null',
			message:  sprintf("'%s' may be null", ts.text(obj, source)),
		});
		return true;
	}
	return false;
}

// `x.p` where some `x.p = …` in the file may have replaced the value the
// type describes (`{ p: null }`, then `x.p = {}` in a loop).
function isWrittenMember(obj, source) {
	if (ts.nodeType(obj) !== 'member_expression') return false;
	let o = ts.childByField(obj, 'object'), p = ts.childByField(obj, 'property');
	return o && p && ts.nodeType(o) === 'identifier'
		&& _written[ts.text(o, source) + '.' + ts.text(p, source)] === true;
}

function objectType(obj, source, uri, scopeMap) {
	let scope = scopeAtOffset(scopeMap, ts.startByte(obj));
	return ts.nodeType(obj) === 'identifier'
		? (scopeGet(scope, ts.text(obj, source)) ?? UNKNOWN)
		: inferNode(obj, source, uri, scope, 0);
}

let _walk;

_walk = function(node, source, uri, scopeMap, lineTable, diags, strict) {
	if (!node) return;
	let nt = ts.nodeType(node);

	if (nt === 'call_expression') {
		let callee = ts.childByField(node, 'function');
		if (callee) {
			if (ts.nodeType(callee) === 'identifier') {
				let scope = scopeAtOffset(scopeMap, ts.startByte(callee));
				let calleeType = scopeGet(scope, ts.text(callee, source)) ?? UNKNOWN;
				if (!isCallable(calleeType)) {
					push(diags, {
						range:    rangeOf(source, lineTable, callee),
						severity: SEVERITY_ERROR,
						source:   'ucode-analyzer',
						code:     'not-a-function',
						message:  sprintf("'%s' is not a function (type: %s)", ts.text(callee, source), calleeType.kind),
					});
				}
			} else {
				_walk(callee, source, uri, scopeMap, lineTable, diags, strict);
			}
		}
		let args = ts.childByField(node, 'arguments');
		if (args) {
			for (let i = 0; i < ts.namedChildCount(args); i++)
				_walk(ts.namedChild(args, i), source, uri, scopeMap, lineTable, diags, strict);
		}
		return;
	}

	if (nt === 'member_expression') {
		let obj  = ts.childByField(node, 'object');
		let prop = ts.childByField(node, 'property');
		// Optional-chaining (obj?.prop) is the null-safe access form: the runtime
		// short-circuits to null when obj is null, so a null/nullable object is
		// expected here and must not be flagged. Property checks still apply.
		let optChain = ts.childByField(node, 'optional_chain') !== null;
		if (obj) {
			let objType = isWrittenMember(obj, source) ? UNKNOWN : objectType(obj, source, uri, scopeMap);
			if (!nullDiag(obj, objType, optChain, source, lineTable, diags, strict)
			    && prop && ts.nodeType(prop) === 'property_identifier' && !isAssignmentTarget(node) && !isDeleteTarget(node)
			           && !(ts.nodeType(obj) === 'identifier' && _written[ts.text(obj, source) + '.' + ts.text(prop, source)])) {
				let field = unknownFieldOf(objType, ts.text(prop, source));
				if (field !== null) {
					push(diags, {
						range:    rangeOf(source, lineTable, prop),
						severity: SEVERITY_WARNING,
						source:   'ucode-analyzer',
						code:     'unknown-property',
						message:  sprintf("Property '%s' does not exist on this type", field),
					});
				}
			}
			// Recurse into the object to catch errors nested within it.
			if (ts.nodeType(obj) !== 'identifier') _walk(obj, source, uri, scopeMap, lineTable, diags, strict);
		}
		return;
	}

	// `obj[i]` fails on null like `obj.p` (read and write); `obj?.[i]` is safe.
	if (nt === 'subscript_expression') {
		let obj = ts.childByField(node, 'object');
		if (obj) {
			if (!isWrittenMember(obj, source))
				nullDiag(obj, objectType(obj, source, uri, scopeMap),
				         ts.childByField(node, 'optional_chain') !== null, source, lineTable, diags, strict);
			if (ts.nodeType(obj) !== 'identifier') _walk(obj, source, uri, scopeMap, lineTable, diags, strict);
		}
		let idx = ts.childByField(node, 'index');
		if (idx) _walk(idx, source, uri, scopeMap, lineTable, diags, strict);
		return;
	}

	if (nt === 'for_in_statement') {
		let right = ts.childByField(node, 'object');
		if (right) {
			let scope = scopeAtOffset(scopeMap, ts.startByte(right));
			let iterType = inferNode(right, source, uri, scope, 0);
			if (isNonIterable(iterType)) {
				push(diags, {
					range:    rangeOf(source, lineTable, right),
					severity: SEVERITY_WARNING,
					source:   'ucode-analyzer',
					code:     'for-in-non-iterable',
					message:  sprintf("Cannot iterate over type '%s'",
					    iterType.kind === 'primitive' ? iterType.name : iterType.kind),
				});
			}
			_walk(right, source, uri, scopeMap, lineTable, diags, strict);
		}
		let body = ts.childByField(node, 'body');
		if (body) _walk(body, source, uri, scopeMap, lineTable, diags, strict);
		return;
	}

	if (nt === 'import_statement') return;

	let n = ts.namedChildCount(node);
	for (let i = 0; i < n; i++)
		_walk(ts.namedChild(node, i), source, uri, scopeMap, lineTable, diags, strict);
};

export function typeErrors(uri, doc) {
	let diags = [];
	let root = ts.rootNode(doc.tree);
	let strict = isStrict(root, doc.text);
	_written = writtenMembers(root, doc.text);
	_walk(root, doc.text, uri, doc.scopeMap, doc.lineTable, diags, strict);
	_written = {};
	return diags;
};
