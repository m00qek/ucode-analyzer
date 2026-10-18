import * as ts from 'tree_sitter';
import { positionToOffset } from 'ucode_analyzer.code_analysis.positions';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { typeToString } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { unify, substitute, returnOf } from 'ucode_analyzer.code_analysis.types.unifier';

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

// The 0-based index of the argument at offset: the separating commas before
// it. Those of nested calls belong to deeper nodes; a comma not yet followed by
// an argument (`f(1, |)`) sits in an ERROR.
function activeParam(argsNode, offset) {
	let count = 0;
	for (let c in ts.children(argsNode)) {
		let commas = (ts.nodeType(c) === 'ERROR') ? ts.children(c) : [c];
		for (let t in commas)
			if (!ts.isNamed(t) && ts.nodeType(t) === ',' && ts.startByte(t) < offset) count++;
	}
	return count;
}

const CALLEES = {
	identifier: true, member_expression: true, subscript_expression: true,
	call_expression: true, parenthesized_expression: true,
};
const OPENERS = { '(': true, '[': true, '{': true };
const CLOSERS = { ')': true, ']': true, '}': true };

// The callee ending at byte `end` inside `node`: a statement or assignment
// that the recovery left before the ERROR ends in it (`x = f`, `let x = f`).
function calleeEndingAt(node, end) {
	while (node && ts.endByte(node) === end && !CALLEES[ts.nodeType(node)]) {
		let n = ts.namedChildCount(node);
		node = n ? ts.namedChild(node, n - 1) : null;
	}
	return (node && ts.endByte(node) === end && CALLEES[ts.nodeType(node)]) ? node : null;
}

// The node before `node` among its parent's children.
function prevSibling(node) {
	let prev = null;
	for (let c in ts.children(ts.parent(node))) {
		if (ts.startByte(c) >= ts.startByte(node)) break;
		prev = c;
	}
	return prev;
}

// An unfinished call the parser could not recover (`f(1, ` at the end of the
// file) is a flat run of tokens in an ERROR, which ends before the blanks up
// to the cursor: find its innermost unclosed `(` that follows a callee, and
// the arguments and commas after it.
function unfinishedCall(root, text, offset) {
	let last = offset - 1;
	while (last > 0 && index(" \t\r\n", substr(text, last, 1)) >= 0) last--;
	let err = ts.descendantAt(root, max(last, 0));
	while (err && ts.nodeType(err) !== 'ERROR') err = ts.parent(err);
	if (!err) return null;

	let toks = ts.children(err);
	let open = [];
	for (let i = 0; i < length(toks) && ts.startByte(toks[i]) < offset; i++) {
		let t = ts.nodeType(toks[i]);
		if (ts.isNamed(toks[i])) continue;
		if (OPENERS[t]) push(open, i);
		else if (CLOSERS[t] && length(open)) pop(open);
	}

	for (let k = length(open) - 1; k >= 0; k--) {
		let i = open[k];
		if (ts.nodeType(toks[i]) !== '(') continue;
		let start = ts.startByte(toks[i]);
		let fnNode = (i > 0) ? calleeEndingAt(toks[i - 1], start)
			: (prevSibling(err) ? calleeEndingAt(prevSibling(err), start) : null);
		if (!fnNode) continue;

		let args = [], commas = 0, depth = 0;
		for (let j = i + 1; j < length(toks) && ts.startByte(toks[j]) < offset; j++) {
			let t = ts.nodeType(toks[j]);
			if (ts.isNamed(toks[j])) { if (!depth) push(args, toks[j]); }
			else if (OPENERS[t]) depth++;
			else if (CLOSERS[t]) depth--;
			else if (t === ',' && !depth) commas++;
		}
		return { fnNode, args, active: commas };
	}
	return null;
}

// The call around offset: its callee, its argument nodes and the index of
// the argument at offset.
function callAt(root, text, offset) {
	let callNode = enclosingCall(root, offset);
	if (!callNode) return unfinishedCall(root, text, offset);

	let fnNode   = ts.childByField(callNode, 'function');
	let argsNode = ts.childByField(callNode, 'arguments');
	if (!fnNode || !argsNode) return null;
	return { fnNode, args: ts.namedChildren(argsNode), active: activeParam(argsNode, offset) };
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
	let ret = returnOf(fnType);
	let retStr = (ret && ret.kind !== 'unknown') ? ': ' + typeToString(ret) : '';
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
	let call   = callAt(ts.rootNode(doc.tree), doc.text, offset);
	if (!call) return null;

	let fnNode  = call.fnNode;
	let scope   = scopeAtOffset(doc.scopeMap, offset);
	let fnType  = inferNode(fnNode, doc.text, uri, scope);
	if (!fnType || fnType.kind !== 'function') return null;

	// Resolve generic type parameters from the arguments already supplied.
	// Unifying each argument's inferred type against its declared parameter type
	// builds bindings like {T: int}, then substitute applies them to the whole
	// function type so the label shows concrete types instead of T.
	let bindings = {};
	let args = call.args;
	for (let i = 0; i < length(args); i++) {
		let paramType = (i < length(fnType.params)) ? (fnType.params[i].type ?? { kind: 'unknown' }) : { kind: 'unknown' };
		unify(paramType, inferNode(args[i], doc.text, uri, scope), bindings, 0);
	}
	let concreteFnType = substitute(fnType, bindings);

	let fnName = ts.text(fnNode, doc.text);
	let sig    = buildSignature(fnName, concreteFnType);
	let active = call.active;
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
