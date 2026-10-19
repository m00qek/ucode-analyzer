// JSDoc self-consistency: flag a documented @param whose name matches no actual
// parameter of the function it documents (a typo or a stale name after a rename).
//
// This is a documentation-consistency check, NOT a runtime-error claim — which is
// what makes it precision-safe in a language whose runtime tolerates almost every
// call-shape mismatch (see docs/decisions.md, "Won't-do: builtin call validation"). The
// function's formal parameters are ground truth; a @param naming something else is
// unambiguously wrong.
//
// False-positive-free across every @param shape because parseDoc reduces each to a
// bare root name: plain `x`, optional `[x]`, rest `...args` (name `args`), and a
// property path `opts.count` (name `opts`, the `.count` parsed as description) all
// yield a root that must be a real parameter. Only the documented-but-absent case
// is reported; a missing @param (incomplete docs) is not flagged.
//
// Scope: function declarations, a function expression or arrow that is the
// whole initializer of a single-declarator let/const (`const f = function(…)`)
// (with several declarators the doc is ambiguous), and one that is the value of
// an object's member, documented before its key.

import * as ts from 'tree_sitter';
import { paramNodes } from 'ucode_analyzer.code_analysis.ast_text';
import { parseDoc } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { precedingDocNode, offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

// The set of formal parameter names of a function node (identifiers and the inner
// identifier of a `...rest` element).
function formalParamNames(fn, source) {
	let names = {};
	for (let p in paramNodes(fn))
		names[ts.text(p.node, source)] = true;
	return names;
}

function checkFn(fn, source, lineTable, out) {
	let commentNode = precedingDocNode(fn, source);
	if (!commentNode) return;
	let doc = parseDoc(ts.text(commentNode, source));
	if (!doc || !length(doc.params)) return;

	let formals = formalParamNames(fn, source);
	let base = ts.startByte(commentNode);

	for (let prm in doc.params) {
		if (prm.name === null || exists(formals, prm.name)) continue;
		let s = base + (prm.nameStart ?? 0);
		let e = base + (prm.nameEnd ?? prm.nameStart ?? 0);
		push(out, diagnostic({
				start: offsetToPosition(source, lineTable, s),
				end:   offsetToPosition(source, lineTable, e),
			}, Severity.WARNING, 'jsdoc-param-mismatch', sprintf("@param '%s' does not match any parameter of this function", prm.name)));
	}
}

// A function expression or arrow that a /** */ documents on its own: the value
// of the only declarator of a let/const, or of an object's member.
function isAssignedFn(node) {
	let t = ts.nodeType(node);
	if (t !== 'function_expression' && t !== 'arrow_function') return false;
	let vd = ts.parent(node);
	if (vd && ts.nodeType(vd) === 'pair')
		return ts.startByte(ts.childByField(vd, 'value')) === ts.startByte(node);
	if (!vd || ts.nodeType(vd) !== 'variable_declarator') return false;
	let value = ts.childByField(vd, 'value');
	if (!value || ts.startByte(value) !== ts.startByte(node)) return false;
	let decl = ts.parent(vd);
	return length(filter(ts.namedChildren(decl), (c) => ts.nodeType(c) === 'variable_declarator')) === 1;
}

const FUNCTION_TYPES = ['function_declaration', 'function_expression', 'arrow_function'];

export function jsdocConsistency(doc) {
	let out = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), FUNCTION_TYPES))
		if (ts.nodeType(node) === 'function_declaration' || isAssignedFn(node))
			checkFn(node, doc.text, doc.lineTable, out);
	return out;
};
