import * as ts from 'tree_sitter';
import { rangeOf } from 'language_server.positions';
import { scopeGet } from 'language_server.types.scope';
import { UNKNOWN } from 'language_server.types.type_utils';
import { inferNode } from 'language_server.types.inferrer';
import { scopeAtOffset } from 'language_server.types.scope_walk';

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

let _walk;

_walk = function(node, source, uri, scopeMap, lineTable, diags) {
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
						source:   'ucode-ls',
						code:     'not-a-function',
						message:  sprintf("'%s' is not a function (type: %s)", ts.text(callee, source), calleeType.kind),
					});
				}
			} else {
				_walk(callee, source, uri, scopeMap, lineTable, diags);
			}
		}
		let args = ts.childByField(node, 'arguments');
		if (args) {
			for (let i = 0; i < ts.namedChildCount(args); i++)
				_walk(ts.namedChild(args, i), source, uri, scopeMap, lineTable, diags);
		}
		return;
	}

	if (nt === 'member_expression') {
		let obj  = ts.childByField(node, 'object');
		let prop = ts.childByField(node, 'property');
		if (obj) {
			let scope = scopeAtOffset(scopeMap, ts.startByte(obj));
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
			if (ts.nodeType(obj) !== 'identifier') _walk(obj, source, uri, scopeMap, lineTable, diags);
		}
		return;
	}

	if (nt === 'for_in_statement') {
		let right = ts.childByField(node, 'right');
		if (right) {
			let scope = scopeAtOffset(scopeMap, ts.startByte(right));
			let iterType = inferNode(right, source, uri, scope, 0);
			if (isNonIterable(iterType)) {
				push(diags, {
					range:    rangeOf(source, lineTable, right),
					severity: SEVERITY_WARNING,
					source:   'ucode-ls',
					code:     'for-in-non-iterable',
					message:  sprintf("Cannot iterate over type '%s'",
					    iterType.kind === 'primitive' ? iterType.name : iterType.kind),
				});
			}
			_walk(right, source, uri, scopeMap, lineTable, diags);
		}
		let body = ts.childByField(node, 'body');
		if (body) _walk(body, source, uri, scopeMap, lineTable, diags);
		return;
	}

	if (nt === 'import_statement') return;

	let n = ts.namedChildCount(node);
	for (let i = 0; i < n; i++)
		_walk(ts.namedChild(node, i), source, uri, scopeMap, lineTable, diags);
};

export function typeErrors(uri, doc) {
	let diags = [];
	_walk(ts.rootNode(doc.tree), doc.text, uri, doc.scopeMap, doc.lineTable, diags);
	return diags;
};
