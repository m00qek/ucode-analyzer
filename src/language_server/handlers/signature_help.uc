import * as ts from 'tree_sitter';
import { positionToOffset } from 'language_server.positions';
import { inferNode } from 'language_server.types.inferrer';
import { scopeAtOffset } from 'language_server.types.scope_walk';
import { typeToString } from 'language_server.types.doc_parser';
import { unify, substitute } from 'language_server.types.unifier';

// Walk the tree depth-first; return the innermost call_expression whose
// arguments node contains offset.
function enclosingCall(root, offset) {
	function walk(node) {
		let count = ts.namedChildCount(node);
		for (let i = 0; i < count; i++) {
			let child = ts.namedChild(node, i);
			if (ts.startByte(child) > offset || ts.endByte(child) < offset) continue;
			let r = walk(child);
			if (r) return r;
		}
		if (ts.nodeType(node) === 'call_expression') {
			let argsNode = ts.childByField(node, 'arguments');
			if (argsNode && ts.startByte(argsNode) <= offset && offset <= ts.endByte(argsNode))
				return node;
		}
		return null;
	}
	return walk(root);
}

// Count arguments (named children of arguments node) whose start byte is
// strictly before offset — gives the 0-based active parameter index.
function activeParam(argsNode, offset) {
	let count = 0;
	let args = ts.namedChildren(argsNode);
	for (let i = 0; i < length(args); i++)
		if (ts.startByte(args[i]) < offset) count++;
	return count;
}

// Count UTF-16 code units in a UTF-8 string, as required by the LSP spec for
// label offset fields.  ASCII strings (the common case for identifiers and
// type names) have length == UTF-16 length, but 4-byte code points (U+10000+)
// consume two UTF-16 code units so we count them as 2.
function utf16Len(s) {
	let n = 0;
	let i = 0;
	let len = length(s);
	while (i < len) {
		let b = ord(substr(s, i, 1));
		if (b < 0x80)      { n += 1; i += 1; }
		else if (b < 0xE0) { n += 1; i += 2; }
		else if (b < 0xF0) { n += 1; i += 3; }
		else               { n += 2; i += 4; }
	}
	return n;
}

// Build the signature label and parameter ranges from a function type.
// Returns { label, parameters: [{label: [start, end]}, ...] }.
function buildSignature(name, fnType) {
	let params = fnType.params ?? [];
	let parts  = [];
	for (let i = 0; i < length(params); i++) {
		let p = params[i];
		push(parts, p.name + (p.type ? ': ' + typeToString(p.type) : ''));
	}
	let retStr = (fnType['return'] && fnType['return'].kind !== 'unknown')
		? ': ' + typeToString(fnType['return']) : '';
	let label = name + '(' + join(', ', parts) + ')' + retStr;

	let paramLabels = [];
	let base = utf16Len(name) + 1;  // after '('
	for (let i = 0; i < length(parts); i++) {
		let s = base;
		let e = base + utf16Len(parts[i]);
		push(paramLabels, { label: [s, e] });
		base = e + 2;  // ', '
	}
	return { label, parameters: paramLabels };
}

export function signatureHelp(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let callNode = enclosingCall(root, offset);
	if (!callNode) return null;

	let fnNode   = ts.childByField(callNode, 'function');
	let argsNode = ts.childByField(callNode, 'arguments');
	if (!fnNode || !argsNode) return null;

	let scope   = scopeAtOffset(doc.scopeMap, offset);
	let fnType  = inferNode(fnNode, doc.text, uri, scope);
	if (!fnType || fnType.kind !== 'function') return null;

	// Resolve generic type parameters from the arguments already supplied.
	// Unifying each argument's inferred type against its declared parameter type
	// builds bindings like {T: int}, then substitute applies them to the whole
	// function type so the label shows concrete types instead of T.
	let bindings = {};
	let args = ts.namedChildren(argsNode);
	for (let i = 0; i < length(args); i++) {
		let paramType = (i < length(fnType.params)) ? (fnType.params[i].type ?? { kind: 'unknown' }) : { kind: 'unknown' };
		unify(paramType, inferNode(args[i], doc.text, uri, scope), bindings, 0);
	}
	let concreteFnType = substitute(fnType, bindings);

	let fnName = ts.text(fnNode, doc.text);
	let sig    = buildSignature(fnName, concreteFnType);
	let active = activeParam(argsNode, offset);
	if (length(sig.parameters) > 0)
		active = min(active, length(sig.parameters) - 1);
	else
		active = null;

	return {
		signatures:      [sig],
		activeSignature: 0,
		activeParameter: active,
	};
};
