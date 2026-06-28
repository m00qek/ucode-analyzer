import * as ts from 'tree_sitter';
import { offsetToPosition, buildLineTable } from 'language_server.positions';

let SEVERITY_WARNING = 2;

function rangeOf(text, lineTable, node) {
	let start = offsetToPosition(text, lineTable, ts.startByte(node));
	let end   = offsetToPosition(text, lineTable, ts.endByte(node));
	return { start, end };
}

// Collect the set of all identifier texts that appear in the tree
// at any position OTHER than their own declaration site.
// We use a two-pass approach:
//   Pass 1: collect every declaration { nameText, declByte } from
//           lexical_declaration and function_declaration nodes.
//   Pass 2: count references — any identifier whose text matches a
//           declared name but whose startByte != declByte is a use.
//
// A declaration is "unused" if no such use exists AND it is not exported.

// Return true if `node` is inside an export_statement.
function isExported(node) {
	let p = ts.parent(node);
	while (p) {
		if (ts.nodeType(p) === 'export_statement') return true;
		if (ts.nodeType(p) === 'program') break;
		p = ts.parent(p);
	}
	return false;
}

// Collect all top-level and nested declarations.
// Each entry: { name, declByte, nameNode }
function collectDeclarations(root, source, out) {
	function walk(node) {
		let nt = ts.nodeType(node);

		if (nt === 'lexical_declaration') {
			for (let i = 0; i < ts.namedChildCount(node); i++) {
				let vd = ts.namedChild(node, i);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nameNode = ts.childByField(vd, 'name');
				if (nameNode && ts.nodeType(nameNode) === 'identifier')
					push(out, { name: ts.text(nameNode, source), declByte: ts.startByte(nameNode), nameNode });
			}
			// Walk the initializer values for nested declarations.
			for (let i = 0; i < ts.namedChildCount(node); i++) {
				let vd = ts.namedChild(node, i);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let val = ts.childByField(vd, 'value');
				if (val) walk(val);
			}
			return;
		}

		if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(node, 0);
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				push(out, { name: ts.text(nameNode, source), declByte: ts.startByte(nameNode), nameNode });
			let body = ts.childByField(node, 'body');
			if (body) walk(body);
			return;
		}

		if (nt === 'export_statement') {
			let inner = ts.namedChild(node, 0);
			if (inner) walk(inner);
			return;
		}

		if (nt === 'arrow_function' || nt === 'function_expression') {
			let body = ts.childByField(node, 'body');
			if (body) walk(body);
			return;
		}

		if (nt === 'statement_block' || nt === 'program') {
			for (let i = 0; i < ts.namedChildCount(node); i++)
				walk(ts.namedChild(node, i));
			return;
		}
	}
	walk(root);
}

// Collect the startByte of every identifier occurrence (including shorthand
// property `{ x }`) in the tree that matches targetName.
// Skips formal_parameters to avoid treating inner function params with the same
// name as uses of the outer variable being checked.
function collectAllIdentifierBytes(node, source, targetName, out) {
	let nt = ts.nodeType(node);
	if (nt === 'formal_parameters') return;
	if ((nt === 'identifier' || nt === 'shorthand_property_identifier') &&
	    ts.text(node, source) === targetName)
		push(out, ts.startByte(node));
	for (let i = 0; i < ts.namedChildCount(node); i++)
		collectAllIdentifierBytes(ts.namedChild(node, i), source, targetName, out);
}

export function unusedVars(doc) {
	let root = ts.rootNode(doc.tree);
	let source = doc.text;
	let lineTable = buildLineTable(source);

	let decls = [];
	collectDeclarations(root, source, decls);

	let diags = [];
	for (let i = 0; i < length(decls); i++) {
		let decl = decls[i];

		// Exported names are consumed externally — never warn.
		if (isExported(decl.nameNode)) continue;

		// Collect all identifier bytes for this name in the whole file.
		let allBytes = [];
		collectAllIdentifierBytes(root, source, decl.name, allBytes);

		// If every occurrence is the declaration itself, it is unused.
		// (The declaration byte always appears in allBytes.)
		let hasUse = false;
		for (let j = 0; j < length(allBytes); j++) {
			if (allBytes[j] !== decl.declByte) { hasUse = true; break; }
		}
		if (!hasUse)
			push(diags, {
				range:    rangeOf(source, lineTable, decl.nameNode),
				severity: SEVERITY_WARNING,
				message:  sprintf("'%s' is declared but never used", decl.name),
			});
	}
	return diags;
};
