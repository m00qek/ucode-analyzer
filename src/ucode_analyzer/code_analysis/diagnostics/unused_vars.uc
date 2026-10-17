import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { identifierOccurrences, namedNonComments } from 'ucode_analyzer.code_analysis.ast_text';

let SEVERITY_WARNING = 2;

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

// Collect all top-level and nested declarations.
// Each entry: { name, declByte, nameNode }
function collectDeclarations(root, source, out) {
	function walk(node) {
		let nt = ts.nodeType(node);

		// Import-introduced names are handled by unused_imports.uc — skip here.
		if (nt === 'import_statement') return;

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
			let nameNode = ts.childByField(node, 'name');
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				push(out, { name: ts.text(nameNode, source), declByte: ts.startByte(nameNode), nameNode });
			let body = ts.childByField(node, 'body');
			if (body) walk(body);
			return;
		}

		if (nt === 'export_statement') {
			for (let inner in namedNonComments(node)) walk(inner);
			return;
		}

		if (nt === 'arrow_function' || nt === 'function_expression') {
			let body = ts.childByField(node, 'body');
			if (body) walk(body);
			return;
		}

		// Default: recurse into all named children so declarations inside
		// if/while/for/try bodies are not missed.
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i));
	}
	walk(root);
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
			push(diags, {
				range:    rangeOf(source, lineTable, decl.nameNode),
				severity: SEVERITY_WARNING,
				source:   'ucode-analyzer',
				code:     'unused-var',
				message:  sprintf("'%s' is declared but never used", decl.name),
			});
	}
	return diags;
};
