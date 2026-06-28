import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_language_server.positions';
import { buildScope, inferNode } from 'ucode_language_server.types.inferrer';
import { typeToString } from 'ucode_language_server.types.doc_parser';

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
	let base = length(name) + 1;  // after '('
	for (let i = 0; i < length(parts); i++) {
		let s = base;
		let e = base + length(parts[i]);
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

	let scope   = buildScope(uri, doc.text, doc.tree, offset);
	let fnType  = inferNode(fnNode, doc.text, uri, scope);
	if (!fnType || fnType.kind !== 'function') return null;

	let fnName = ts.text(fnNode, doc.text);
	let sig    = buildSignature(fnName, fnType);
	let active = activeParam(argsNode, offset);
	active = min(active, length(sig.parameters) - 1);

	return {
		signatures:      [sig],
		activeSignature: 0,
		activeParameter: active,
	};
};
