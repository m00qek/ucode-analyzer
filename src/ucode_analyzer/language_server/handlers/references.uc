import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf } from 'ucode_analyzer.language_server.scope_references';
import { resolveExportIdentity, crossFileRefsOf } from 'ucode_analyzer.language_server.cross_file_refs';

export function references(uri, doc, position, includeDeclaration) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset, includeDeclaration);
	if (!nodes) return null;

	let result = map(nodes, (n) => ({ uri, range: rangeOf(doc.text, doc.lineTable, n) }));

	let identity = resolveExportIdentity(uri, doc, offset);
	if (identity) {
		// crossFileRefsOf includes the export's own declaration (in the declaring
		// module) when the cursor is in an importing file. Honor
		// includeDeclaration:false by dropping that one range.
		let declPos = null;
		if (includeDeclaration === false) {
			let loc = dag.resolveExportLocation(identity.declaringUri, identity.exportName);
			let exp = dag.resolveExport(loc.uri, loc.name);
			if (exp && exp.position) declPos = { uri: loc.uri, position: exp.position };
		}
		for (let cr in crossFileRefsOf(identity.declaringUri, identity.exportName, uri)) {
			for (let range in cr.refRanges) {
				if (declPos && cr.uri === declPos.uri &&
				    range.start.line === declPos.position.line &&
				    range.start.character === declPos.position.character)
					continue;
				push(result, { uri: cr.uri, range });
			}
		}
	}

	return result;
};
