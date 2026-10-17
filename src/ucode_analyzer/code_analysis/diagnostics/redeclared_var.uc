import * as ts from 'tree_sitter';
import { rangeOf, STATEMENT_LISTS } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

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
				push(diags, diagnostic(rangeOf(source, lineTable, nameNode), Severity.ERROR, 'redeclared-var',
					sprintf("'%s' is already declared in this scope", name)));
			} else {
				seen[name] = true;
			}
		}
	}
}

export function redeclaredVars(doc) {
	let diags = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), STATEMENT_LISTS))
		checkBlock(node, doc.text, doc.lineTable, diags);
	return diags;
};
