import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';

// LSP SymbolKind constants
let KIND_FUNCTION  = 12;
let KIND_VARIABLE  = 13;
let KIND_CONSTANT  = 14;

// Recursively collect DocumentSymbol entries from node into result.
//
// Recognized binding sites:
//   program / statement_block  → recurse into each named child
//   export_statement           → unwrap the inner declaration
//   function_declaration       → emit FUNCTION symbol, recurse into body
//   lexical_declaration        → emit VARIABLE/CONSTANT/FUNCTION per declarator;
//                                recurse into the initializer value for nested decls
//   arrow_function /
//   function_expression        → recurse into body (reached from lex_decl values)
//   object                     → emit FUNCTION symbols for function-valued pairs
//
// Everything else is a leaf for symbol purposes.
function walkSymbols(node, text, lineTable, result) {
	let nt = ts.nodeType(node);

	// ── Containers: recurse into statements ────────────────────────────────
	if (nt === 'program' || nt === 'statement_block') {
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walkSymbols(ts.namedChild(node, i), text, lineTable, result);
		return;
	}

	// ── Export: unwrap and process the inner declaration ───────────────────
	if (nt === 'export_statement') {
		let inner = ts.namedChild(node, 0);
		if (inner) walkSymbols(inner, text, lineTable, result);
		return;
	}

	// ── Function declaration ────────────────────────────────────────────────
	if (nt === 'function_declaration') {
		let nameNode = ts.namedChild(node, 0);
		if (!nameNode) return;
		push(result, {
			name:           ts.text(nameNode, text),
			kind:           KIND_FUNCTION,
			range:          rangeOf(text, lineTable, node),
			selectionRange: rangeOf(text, lineTable, nameNode),
		});
		let body = ts.childByField(node, 'body');
		if (body) walkSymbols(body, text, lineTable, result);
		return;
	}

	// ── Lexical declaration (let / const) ───────────────────────────────────
	if (nt === 'lexical_declaration') {
		let kw = ts.child(node, 0);
		let isConst = kw && ts.text(kw, text) === 'const';
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (!nameNode) continue;
			let valNode = ts.childByField(vd, 'value');
			let kind = isConst ? KIND_CONSTANT : KIND_VARIABLE;
			if (valNode) {
				let vt = ts.nodeType(valNode);
				if (vt === 'arrow_function' || vt === 'function_expression')
					kind = KIND_FUNCTION;
			}
			push(result, {
				name:           ts.text(nameNode, text),
				kind,
				range:          rangeOf(text, lineTable, node),
				selectionRange: rangeOf(text, lineTable, nameNode),
			});
			if (valNode) walkSymbols(valNode, text, lineTable, result);
		}
		return;
	}

	// ── Function values: recurse into body for nested declarations ──────────
	if (nt === 'arrow_function' || nt === 'function_expression') {
		let body = ts.childByField(node, 'body');
		if (body) walkSymbols(body, text, lineTable, result);
		return;
	}

	// ── Object literal: emit function-valued properties ─────────────────────
	if (nt === 'object') {
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let pair = ts.namedChild(node, i);
			if (ts.nodeType(pair) !== 'pair') continue;
			let keyNode = ts.childByField(pair, 'key');
			let valNode = ts.childByField(pair, 'value');
			if (!keyNode || !valNode) continue;
			let vt = ts.nodeType(valNode);
			if (vt === 'arrow_function' || vt === 'function_expression') {
				push(result, {
					name:           ts.text(keyNode, text),
					kind:           KIND_FUNCTION,
					range:          rangeOf(text, lineTable, pair),
					selectionRange: rangeOf(text, lineTable, keyNode),
				});
				walkSymbols(valNode, text, lineTable, result);
			}
		}
		return;
	}
}

export function documentSymbols(doc) {
	let text      = doc.text;
	let lineTable = buildLineTable(text);
	let result    = [];
	walkSymbols(ts.rootNode(doc.tree), text, lineTable, result);
	return result;
};
