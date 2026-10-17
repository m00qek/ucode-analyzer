import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { identifierOccurrences } from 'ucode_analyzer.code_analysis.ast_text';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

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
		p = ts.parent(p);
	}
	return false;
}

// Collect every declaration, nested ones included, but not those inside
// parameter lists. Import-introduced names are handled by unused_import.uc.
// Each entry: { name, declByte, nameNode }
function collectDeclarations(root, source, out) {
	function add(nameNode) {
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			push(out, { name: ts.text(nameNode, source), declByte: ts.startByte(nameNode), nameNode });
	}
	let skipEnd = -1;  // end of the formal_parameters being skipped
	for (let node in ts.descendants(root, ['lexical_declaration', 'function_declaration', 'formal_parameters'])) {
		if (ts.startByte(node) < skipEnd) continue;
		let nt = ts.nodeType(node);
		if (nt === 'formal_parameters') {
			skipEnd = ts.endByte(node);
		} else if (nt === 'function_declaration') {
			add(ts.childByField(node, 'name'));
		} else {
			for (let vd in ts.namedChildren(node))
				if (ts.nodeType(vd) === 'variable_declarator')
					add(ts.childByField(vd, 'name'));
		}
	}
}

export function unusedVars(doc) {
	let root = ts.rootNode(doc.tree);
	let source = doc.text;
	let lineTable = doc.lineTable;

	let decls = [];
	collectDeclarations(root, source, decls);

	// Skip formal_parameters so an inner function's params don't count as uses of
	// an outer variable of the same name.
	let byName = identifierOccurrences(root, source, true);

	let diags = [];
	for (let i = 0; i < length(decls); i++) {
		let decl = decls[i];

		// Exported names are consumed externally — never warn.
		if (isExported(decl.nameNode)) continue;

		// If every occurrence of this name is the declaration byte itself, it is unused.
		let allBytes = byName[decl.name] ?? [];
		let hasUse = false;
		for (let j = 0; j < length(allBytes); j++) {
			if (allBytes[j] !== decl.declByte) { hasUse = true; break; }
		}
		if (!hasUse)
			push(diags, diagnostic(rangeOf(source, lineTable, decl.nameNode), Severity.WARNING, 'unused-var',
				sprintf("'%s' is declared but never used", decl.name)));
	}
	return diags;
};
