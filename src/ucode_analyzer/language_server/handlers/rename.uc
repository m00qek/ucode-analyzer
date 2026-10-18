import * as ts from 'tree_sitter';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf } from 'ucode_analyzer.code_analysis.scope_references';
import { resolveExportIdentity, declaringEntry, importersOf, importerEntry } from 'ucode_analyzer.code_analysis.cross_file_refs';

// The rename as a plan (see background.uc), one item per importing file.
export function renamePlan(uri, doc, position, newName) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let nodes = referencesOf(root, doc.text, offset);
	if (!nodes) return null;

	let edits = map(nodes, (n) => ({ range: rangeOf(doc.text, doc.lineTable, n), newText: newName }));

	let changes = { [uri]: edits };

	let identity = resolveExportIdentity(uri, doc, offset);
	if (!identity)
		return { items: [], work: null, finish: () => ({ changes }) };

	let decl = declaringEntry(identity.declaringUri, identity.exportName, uri);
	return {
		items:  importersOf(identity.declaringUri, uri),
		work:   (u) => importerEntry(u, identity.declaringUri, identity.exportName),
		finish: (entries) => {
			for (let cr in [decl, ...entries])
				if (cr && length(cr.renameRanges) > 0)
					changes[cr.uri] = map(cr.renameRanges, (r) => ({ range: r, newText: newName }));
			return { changes };
		},
	};
};

export function rename(uri, doc, position, newName) {
	let p = renamePlan(uri, doc, position, newName);
	return p ? p.finish(map(p.items, p.work)) : null;
};
