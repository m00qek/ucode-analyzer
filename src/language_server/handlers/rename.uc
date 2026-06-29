import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'language_server.positions';
import { referencesOf } from 'language_server.scope_references';
import { resolveExportIdentity, crossFileRefsOf } from 'language_server.cross_file_refs';

export function rename(uri, doc, position, newName) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset);
	if (!nodes) return null;

	let lineTable = buildLineTable(doc.text);
	let edits = map(nodes, (n) => {
		let start = offsetToPosition(doc.text, lineTable, ts.startByte(n));
		let end   = offsetToPosition(doc.text, lineTable, ts.endByte(n));
		return { range: { start, end }, newText: newName };
	});

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
