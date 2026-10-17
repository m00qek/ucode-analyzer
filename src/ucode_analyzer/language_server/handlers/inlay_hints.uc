import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { typeToString } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { InlayHintKind } from 'ucode_analyzer.code_analysis.lsp_types';

let LITERAL_TYPES = {
	number: true, string: true, 'true': true, 'false': true, 'null': true,
};

// Abbreviated type label for inline display: function types collapse to 'fn'
// (full signature is available via hover). Returns null when there is nothing
// useful to show (unknown or unresolvable).
function typeLabel(type) {
	if (!type || type.kind === 'unknown') return null;
	if (type.kind === 'function') return 'fn';
	let s = typeToString(type);
	return (s === '?') ? null : s;
}

function walk(node, source, uri, scopeMap, lineTable, rangeStart, rangeEnd, hints) {
	if (!node) return;

	let nodeStart = ts.startByte(node);
	let nodeEnd   = ts.endByte(node);

	// Skip nodes entirely outside the visible range.
	if (nodeEnd <= rangeStart || nodeStart >= rangeEnd) return;

	let nt = ts.nodeType(node);

	if (nt === 'variable_declarator') {
		let nameNode  = ts.childByField(node, 'name');
		let valueNode = ts.childByField(node, 'value');
		if (nameNode && valueNode && !LITERAL_TYPES[ts.nodeType(valueNode)]) {
			let nameEnd = ts.endByte(nameNode);
			if (nameEnd > rangeStart && nameEnd <= rangeEnd) {
				let scope = scopeAtOffset(scopeMap, nodeStart);
				let type  = inferNode(valueNode, source, uri, scope, 0);
				let label = typeLabel(type);
				if (label) {
					push(hints, {
						position:    offsetToPosition(source, lineTable, nameEnd),
						label:       ': ' + label,
						kind:        InlayHintKind.TYPE,
						paddingLeft: true,
					});
				}
			}
		}
	}

	if (nt === 'call_expression') {
		let fnNode   = ts.childByField(node, 'function');
		let argsNode = ts.childByField(node, 'arguments');
		if (fnNode && argsNode) {
			let scope  = scopeAtOffset(scopeMap, nodeStart);
			let fnType = inferNode(fnNode, source, uri, scope, 0);
			if (fnType && fnType.kind === 'function') {
				let args = ts.namedChildren(argsNode);
				for (let i = 0; i < length(args) && i < length(fnType.params); i++) {
					let param   = fnType.params[i];
					let argNode = args[i];
					if (!param?.name || !argNode) continue;
					// Skip when the argument identifier already matches the param name.
					if (ts.nodeType(argNode) === 'identifier' &&
					    ts.text(argNode, source) === param.name) continue;
					let argStart = ts.startByte(argNode);
					if (argStart >= rangeStart && argStart < rangeEnd) {
						push(hints, {
							position:     offsetToPosition(source, lineTable, argStart),
							label:        param.name + ':',
							kind:         InlayHintKind.PARAMETER,
							paddingRight: true,
						});
					}
				}
			}
		}
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, uri, scopeMap, lineTable, rangeStart, rangeEnd, hints);
}

export function inlayHints(doc, range) {
	let source    = doc.text;
	let uri       = doc.uri;
	let lineTable = doc.lineTable;

	let rangeStart = positionToOffset(source, lineTable, range.start);
	let rangeEnd   = positionToOffset(source, lineTable, range.end);

	let hints = [];
	walk(ts.rootNode(doc.tree), source, uri, doc.scopeMap, lineTable, rangeStart, rangeEnd, hints);
	return hints;
};
