import * as ts from 'tree_sitter';
import { offsetToPosition } from 'code_analysis.positions';

// Nodes whose statement_block bodies are good fold targets.
let BLOCK_PARENTS = {
	function_declaration: true,
	function_expression:  true,
	arrow_function:       true,
	if_statement:         true,
	else_clause:          true,
	while_statement:      true,
	for_statement:        true,
	for_in_statement:     true,
	do_statement:         true,
	try_statement:        true,
	catch_clause:         true,
	finally_clause:       true,
};

function walk(node, source, lineTable, ranges) {
	let nt = ts.nodeType(node);

	if (nt === 'statement_block') {
		let startLine = offsetToPosition(source, lineTable, ts.startByte(node)).line;
		let endLine   = offsetToPosition(source, lineTable, ts.endByte(node) - 1).line;
		if (endLine > startLine)
			push(ranges, { startLine, endLine });
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, ranges);
}

export function foldingRanges(doc) {
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let root      = ts.rootNode(doc.tree);
	let ranges    = [];

	// Statement block ranges (function bodies, if/while/for/try/catch blocks).
	walk(root, source, lineTable, ranges);

	// Import block: consecutive import_statement nodes at the program top level.
	let firstImport = -1;
	let lastImport  = -1;
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let child = ts.namedChild(root, i);
		if (ts.nodeType(child) !== 'import_statement') {
			if (firstImport >= 0) break;
			continue;
		}
		let line = offsetToPosition(source, lineTable, ts.startByte(child)).line;
		if (firstImport < 0) firstImport = line;
		lastImport = offsetToPosition(source, lineTable, ts.endByte(child) - 1).line;
	}
	if (firstImport >= 0 && lastImport > firstImport)
		push(ranges, { startLine: firstImport, endLine: lastImport, kind: 'imports' });

	return ranges;
};
