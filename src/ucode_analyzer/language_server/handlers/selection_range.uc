import * as ts from 'tree_sitter';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { nodeAtOffset } from 'ucode_analyzer.code_analysis.positions';

// Build a SelectionRange chain (innermost → outermost) for one cursor position.
// Each link covers one ancestor node; consecutive nodes with identical ranges
// are collapsed so the client sees only meaningful expansion steps.
function chainFor(root, source, lineTable, position) {
	let offset = positionToOffset(source, lineTable, position);
	let leaf   = nodeAtOffset(root, offset);
	if (!leaf) return null;

	// Collect ranges from leaf to root, deduplicating identical adjacent ranges.
	let ranges = [];
	let cur = leaf;
	while (cur) {
		let r = rangeOf(source, lineTable, cur);
		let last = length(ranges) > 0 ? ranges[length(ranges) - 1] : null;
		if (!last ||
		    last.start.line      !== r.start.line ||
		    last.start.character !== r.start.character ||
		    last.end.line        !== r.end.line ||
		    last.end.character   !== r.end.character)
			push(ranges, r);
		cur = ts.parent(cur);
	}

	// Build the chain from outermost inward so each entry's parent points outward.
	let result = null;
	for (let i = length(ranges) - 1; i >= 0; i--)
		result = { range: ranges[i], parent: result };
	return result;
};

export function selectionRanges(doc, positions) {
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let root      = ts.rootNode(doc.tree);
	let result    = [];
	for (let i = 0; i < length(positions); i++)
		push(result, chainFor(root, source, lineTable, positions[i]));
	return result;
};
