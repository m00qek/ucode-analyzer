import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, buildLineTable } from 'code_analysis.positions';
import { referencesOf } from 'language_server.scope_references';
import { resolveExportIdentity, crossFileRefsOf } from 'language_server.cross_file_refs';

export function references(uri, doc, position, includeDeclaration) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset, includeDeclaration);
	if (!nodes) return null;

	let lineTable = buildLineTable(doc.text);
	let result = map(nodes, (n) => {
		let start = offsetToPosition(doc.text, lineTable, ts.startByte(n));
		let end   = offsetToPosition(doc.text, lineTable, ts.endByte(n));
		return { uri, range: { start, end } };
	});

	let identity = resolveExportIdentity(uri, doc, offset);
	if (identity) {
		for (let cr in crossFileRefsOf(identity.declaringUri, identity.exportName, uri)) {
			for (let range in cr.refRanges)
				push(result, { uri: cr.uri, range });
		}
	}

	return result;
};
