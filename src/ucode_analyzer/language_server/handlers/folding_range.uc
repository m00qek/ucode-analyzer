import * as ts from 'tree_sitter';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';

function walk(node, source, lineTable, ranges) {
	let nt = ts.nodeType(node);

	if (nt === 'statement_block') {
		// A block left open at the end of the file ends at or past the end of
		// its text (a MISSING `}`, or closers mode.parse() appended): it folds
		// to its last line with text, as it does in a large or small file.
		let end = min(ts.endByte(node), length(source));
		while (end > ts.startByte(node) && index(" \t\r\n", substr(source, end - 1, 1)) >= 0) end--;
		let startLine = offsetToPosition(source, lineTable, ts.startByte(node)).line;
		let endLine   = offsetToPosition(source, lineTable, end - 1).line;
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
