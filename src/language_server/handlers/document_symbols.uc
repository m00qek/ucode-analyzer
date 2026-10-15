import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'code_analysis.positions';

// LSP SymbolKind constants
let KIND_FUNCTION  = 12;
let KIND_VARIABLE  = 13;
let KIND_CONSTANT  = 14;

// Recursively collect DocumentSymbol entries from node, returning an array.
// Nested symbols appear as children of their enclosing symbol rather than
// as a flat list — clients that support hierarchical document symbols render
// an outline tree; clients that don't still see the top-level entries.
//
// Recognized binding sites:
//   program / statement_block  → recurse into each named child
//   export_statement           → unwrap the inner declaration
//   function_declaration       → FUNCTION symbol; body contents become children
//   lexical_declaration        → VARIABLE/CONSTANT/FUNCTION per declarator;
//                                function-body contents become children
//   object                     → FUNCTION symbols for function-valued pairs;
//                                their body contents become children
function walkSymbols(node, text, lineTable) {
	let nt = ts.nodeType(node);

	// ── Containers: flatten children into caller's result ──────────────────
	if (nt === 'program' || nt === 'statement_block' || nt === 'statement_list') {
		let result = [];
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let children = walkSymbols(ts.namedChild(node, i), text, lineTable);
			for (let j = 0; j < length(children); j++) push(result, children[j]);
		}
		return result;
	}

	// ── Export: unwrap and process the inner declaration ───────────────────
	if (nt === 'export_statement') {
		let inner = ts.namedChild(node, 0);
		return inner ? walkSymbols(inner, text, lineTable) : [];
	}

	// ── Function declaration ────────────────────────────────────────────────
	if (nt === 'function_declaration') {
		let nameNode = ts.namedChild(node, 0);
		if (!nameNode) return [];
		let body = ts.childByField(node, 'body');
		let children = body ? walkSymbols(body, text, lineTable) : [];
		let sym = {
			name:           ts.text(nameNode, text),
			kind:           KIND_FUNCTION,
			range:          rangeOf(text, lineTable, node),
			selectionRange: rangeOf(text, lineTable, nameNode),
		};
		if (length(children) > 0) sym.children = children;
		return [sym];
	}

	// ── Lexical declaration (let / const) ───────────────────────────────────
	if (nt === 'lexical_declaration') {
		let kw = ts.child(node, 0);
		let isConst = kw && ts.text(kw, text) === 'const';
		let result = [];
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (!nameNode) continue;
			let valNode = ts.childByField(vd, 'value');
			let kind = isConst ? KIND_CONSTANT : KIND_VARIABLE;
			let children = [];
			if (valNode) {
				let vt = ts.nodeType(valNode);
				if (vt === 'arrow_function' || vt === 'function_expression') {
					kind = KIND_FUNCTION;
					let body = ts.childByField(valNode, 'body');
					if (body && ts.nodeType(body) === 'statement_block')
						children = walkSymbols(body, text, lineTable);
				} else {
					children = walkSymbols(valNode, text, lineTable);
				}
			}
			let sym = {
				name:           ts.text(nameNode, text),
				kind,
				range:          rangeOf(text, lineTable, node),
				selectionRange: rangeOf(text, lineTable, nameNode),
			};
			if (length(children) > 0) sym.children = children;
			push(result, sym);
		}
		return result;
	}

	// ── Object literal: emit function-valued properties ─────────────────────
	if (nt === 'object') {
		let result = [];
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let pair = ts.namedChild(node, i);
			if (ts.nodeType(pair) !== 'pair') continue;
			let keyNode = ts.childByField(pair, 'key');
			let valNode = ts.childByField(pair, 'value');
			if (!keyNode || !valNode) continue;
			let vt = ts.nodeType(valNode);
			if (vt === 'arrow_function' || vt === 'function_expression') {
				let body = ts.childByField(valNode, 'body');
				let children = (body && ts.nodeType(body) === 'statement_block')
					? walkSymbols(body, text, lineTable) : [];
				let sym = {
					name:           ts.text(keyNode, text),
					kind:           KIND_FUNCTION,
					range:          rangeOf(text, lineTable, pair),
					selectionRange: rangeOf(text, lineTable, keyNode),
				};
				if (length(children) > 0) sym.children = children;
				push(result, sym);
			}
		}
		return result;
	}

	return [];
}

export function documentSymbols(doc) {
	let text      = doc.text;
	let lineTable = buildLineTable(text);
	return walkSymbols(ts.rootNode(doc.tree), text, lineTable);
};
