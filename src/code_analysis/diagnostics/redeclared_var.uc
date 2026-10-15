import * as ts from 'tree_sitter';
import { rangeOf } from 'code_analysis.positions';

let SEVERITY_ERROR = 1;

// Check direct-child lexical_declarations of a block node for duplicate names.
// "Direct child" means declared in this block, not in a nested sub-block — a
// name declared in an inner block is a fresh scope and is not a redeclaration.
function checkBlock(node, source, lineTable, diags) {
	let seen = {};   // name → { nameNode, declByte } of first declaration

	let count = ts.namedChildCount(node);
	for (let i = 0; i < count; i++) {
		let stmt = ts.namedChild(node, i);
		if (ts.nodeType(stmt) !== 'lexical_declaration') continue;

		for (let j = 0; j < ts.namedChildCount(stmt); j++) {
			let vd = ts.namedChild(stmt, j);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (!nameNode || ts.nodeType(nameNode) !== 'identifier') continue;

			let name = ts.text(nameNode, source);
			if (exists(seen, name)) {
				push(diags, {
					range:    rangeOf(source, lineTable, nameNode),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'redeclared-var',
					message:  sprintf("'%s' is already declared in this scope", name),
				});
			} else {
				seen[name] = true;
			}
		}
	}
}

// Recursively walk the tree; call checkBlock for every scope container.
function walk(node, source, lineTable, diags) {
	let nt = ts.nodeType(node);
	if (nt === 'program' || nt === 'statement_block' || nt === 'statement_list')
		checkBlock(node, source, lineTable, diags);

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, diags);
}

export function redeclaredVars(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let diags     = [];
	walk(root, source, lineTable, diags);
	return diags;
};
