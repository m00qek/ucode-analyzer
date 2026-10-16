// JSDoc self-consistency: flag a documented @param whose name matches no actual
// parameter of the function it documents (a typo or a stale name after a rename).
//
// This is a documentation-consistency check, NOT a runtime-error claim — which is
// what makes it precision-safe in a language whose runtime tolerates almost every
// call-shape mismatch (see decisions.md, "Won't-do: builtin call validation"). The
// function's formal parameters are ground truth; a @param naming something else is
// unambiguously wrong.
//
// False-positive-free across every @param shape because parseDoc reduces each to a
// bare root name: plain `x`, optional `[x]`, rest `...args` (name `args`), and a
// property path `opts.count` (name `opts`, the `.count` parsed as description) all
// yield a root that must be a real parameter. Only the documented-but-absent case
// is reported; a missing @param (incomplete docs) is not flagged.
//
// Scope: function_declaration (covers the hand-written declaration stubs and most
// user functions). Assigned function expressions and object methods are a possible
// follow-up.

import * as ts from 'tree_sitter';
import { firstNamed } from 'code_analysis.ast_text';
import { parseDoc } from 'code_analysis.types.doc_parser';
import { precedingDocNode, offsetToPosition } from 'code_analysis.positions';

let SEVERITY_WARNING = 2;

// The set of formal parameter names of a function node (identifiers and the inner
// identifier of a `...rest` element).
function formalParamNames(fn, source) {
	let names = {};
	let params = ts.childByField(fn, 'parameters');
	if (!params) return names;
	for (let i = 0; i < ts.namedChildCount(params); i++) {
		let p = ts.namedChild(params, i);
		let pt = ts.nodeType(p);
		if (pt === 'identifier') {
			names[ts.text(p, source)] = true;
		} else if (pt === 'rest_element') {
			let inner = firstNamed(p);
			if (inner && ts.nodeType(inner) === 'identifier')
				names[ts.text(inner, source)] = true;
		}
	}
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
		push(out, {
			range: {
				start: offsetToPosition(source, lineTable, s),
				end:   offsetToPosition(source, lineTable, e),
			},
			severity: SEVERITY_WARNING,
			source:   'ucode-ls',
			code:     'jsdoc-param-mismatch',
			message:  sprintf("@param '%s' does not match any parameter of this function", prm.name),
		});
	}
}

function walk(node, source, lineTable, out) {
	if (ts.nodeType(node) === 'function_declaration')
		checkFn(node, source, lineTable, out);
	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, out);
}

export function jsdocConsistency(doc) {
	let out = [];
	walk(ts.rootNode(doc.tree), doc.text, doc.lineTable, out);
	return out;
};
