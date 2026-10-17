import * as ts from 'tree_sitter';
import { buildLineTable, positionToOffset, offsetToPosition, findAncestor } from 'ucode_analyzer.code_analysis.positions';

// Find the deepest node whose span contains offset.
// Build a deletion range that removes `specifier` from its `named_imports` siblings.
// Handles first/middle/last positions by absorbing the adjacent comma+whitespace.
function specifierRange(namedImports, specifier, source, lineTable) {
	let specs = [];
	for (let i = 0; i < ts.namedChildCount(namedImports); i++) {
		let c = ts.namedChild(namedImports, i);
		if (ts.nodeType(c) === 'import_specifier') push(specs, c);
	}

	let idx = -1;
	let specStart = ts.startByte(specifier);
	for (let i = 0; i < length(specs); i++) {
		if (ts.startByte(specs[i]) === specStart) { idx = i; break; }
	}
	if (idx < 0) return null;

	let n = length(specs);
	let start, end;
	if (idx < n - 1) {
		// Not last: eat from start of this specifier to start of next (absorbs trailing ", ")
		start = ts.startByte(specs[idx]);
		end   = ts.startByte(specs[idx + 1]);
	} else if (n > 1) {
		// Last (not only): eat from end of previous specifier to end of this one (absorbs leading ", ")
		start = ts.endByte(specs[idx - 1]);
		end   = ts.endByte(specs[idx]);
	} else {
		return null;  // only specifier — caller handles whole-statement removal
	}

	return {
		start: offsetToPosition(source, lineTable, start),
		end:   offsetToPosition(source, lineTable, end),
	};
}

export function actionsFor(uri, doc, diagnostics) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let actions   = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'unused-import') continue;

		let offset  = positionToOffset(source, lineTable, diag.range.start);
		let nameNode = ts.descendantAt(root, offset);
		if (!nameNode) continue;

		let importStmt = findAncestor(nameNode, 'import_statement');
		if (!importStmt) continue;

		// Find the named_imports clause (if any) to decide single vs multi specifier.
		let namedImports = null;
		for (let i = 0; i < ts.namedChildCount(importStmt); i++) {
			let c = ts.namedChild(importStmt, i);
			if (ts.nodeType(c) === 'import_clause') {
				for (let j = 0; j < ts.namedChildCount(c); j++) {
					let part = ts.namedChild(c, j);
					if (ts.nodeType(part) === 'named_imports') { namedImports = part; break; }
				}
				break;
			}
		}

		// Count specifiers in named_imports to decide single vs multi.
		let specCount = 0;
		if (namedImports) {
			for (let i = 0; i < ts.namedChildCount(namedImports); i++) {
				if (ts.nodeType(ts.namedChild(namedImports, i)) === 'import_specifier')
					specCount++;
			}
		}

		let edit;
		if (specCount > 1) {
			// Find the import_specifier ancestor of nameNode.
			let specNode = findAncestor(nameNode, 'import_specifier') ?? nameNode;
			let range = specifierRange(namedImports, specNode, source, lineTable);
			if (!range) continue;
			edit = { range, newText: '' };
		} else {
			// Remove the whole statement line (including trailing newline).
			let stmtLine = diag.range.start.line;
			edit = {
				range: {
					start: { line: stmtLine, character: 0 },
					end:   { line: stmtLine + 1, character: 0 },
				},
				newText: '',
			};
		}

		push(actions, {
			title:       sprintf("Remove unused import '%s'", ts.text(nameNode, source)),
			kind:        'quickfix',
			diagnostics: [diag],
			isPreferred: true,
			edit:        { changes: { [uri]: [edit] } },
		});
	}

	return actions;
};
