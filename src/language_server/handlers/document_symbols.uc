import * as ts from 'tree_sitter';
import { offsetToPosition, buildLineTable } from 'language_server.positions';

// LSP SymbolKind constants
let KIND_FUNCTION  = 12;
let KIND_VARIABLE  = 13;
let KIND_CONSTANT  = 14;

function rangeOf(text, lineTable, node) {
	let start = offsetToPosition(text, lineTable, ts.startByte(node));
	let end   = offsetToPosition(text, lineTable, ts.endByte(node));
	return { start, end };
}

function addVarDecl(stmt, text, lineTable, isConst, result) {
	let count = ts.namedChildCount(stmt);
	for (let i = 0; i < count; i++) {
		let vd = ts.namedChild(stmt, i);
		if (ts.nodeType(vd) !== 'variable_declarator') continue;
		let nameNode = ts.childByField(vd, 'name');
		if (!nameNode) continue;
		let name  = ts.text(nameNode, text);
		let valNode = ts.childByField(vd, 'value');
		let kind  = isConst ? KIND_CONSTANT : KIND_VARIABLE;
		if (valNode && ts.nodeType(valNode) === 'arrow_function') kind = KIND_FUNCTION;
		push(result, {
			name,
			kind,
			range:          rangeOf(text, lineTable, stmt),
			selectionRange: rangeOf(text, lineTable, nameNode),
		});
	}
}

export function documentSymbols(doc) {
	let text      = doc.text;
	let lineTable = buildLineTable(text);
	let root      = ts.rootNode(doc.tree);
	let result    = [];

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		let nt   = ts.nodeType(stmt);

		if (nt === 'lexical_declaration') {
			let kw = ts.child(stmt, 0);
			let isConst = kw && ts.text(kw, text) === 'const';
			addVarDecl(stmt, text, lineTable, isConst, result);
		} else if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(stmt, 0);
			if (!nameNode) continue;
			push(result, {
				name:           ts.text(nameNode, text),
				kind:           KIND_FUNCTION,
				range:          rangeOf(text, lineTable, stmt),
				selectionRange: rangeOf(text, lineTable, nameNode),
			});
		} else if (nt === 'export_statement') {
			let decl = ts.namedChild(stmt, 0);
			if (!decl) continue;
			let dt = ts.nodeType(decl);
			if (dt === 'lexical_declaration') {
				let kw = ts.child(decl, 0);
				let isConst = kw && ts.text(kw, text) === 'const';
				addVarDecl(decl, text, lineTable, isConst, result);
			} else if (dt === 'function_declaration') {
				let nameNode = ts.namedChild(decl, 0);
				if (!nameNode) continue;
				push(result, {
					name:           ts.text(nameNode, text),
					kind:           KIND_FUNCTION,
					range:          rangeOf(text, lineTable, stmt),
					selectionRange: rangeOf(text, lineTable, nameNode),
				});
			}
		}
	}

	return result;
};
