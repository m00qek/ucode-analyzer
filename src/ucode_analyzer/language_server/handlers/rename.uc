import * as ts from 'tree_sitter';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf } from 'ucode_analyzer.code_analysis.scope_references';
import { resolveExportIdentity, crossFileRefsOf } from 'ucode_analyzer.code_analysis.cross_file_refs';

export function rename(uri, doc, position, newName) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset);
	if (!nodes) return null;

	let edits = map(nodes, (n) => ({ range: rangeOf(doc.text, doc.lineTable, n), newText: newName }));

	let changes = { [uri]: edits };

	let identity = resolveExportIdentity(uri, doc, offset);
	if (identity) {
		for (let cr in crossFileRefsOf(identity.declaringUri, identity.exportName, uri)) {
			if (length(cr.renameRanges) > 0)
				changes[cr.uri] = map(cr.renameRanges, (r) => ({ range: r, newText: newName }));
		}
	}

	return { changes };
};
