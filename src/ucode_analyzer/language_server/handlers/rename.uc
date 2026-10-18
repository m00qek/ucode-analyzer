import * as ts from 'tree_sitter';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf } from 'ucode_analyzer.code_analysis.scope_references';
import { resolveExportIdentity, crossFileSearch, searchEntry } from 'ucode_analyzer.code_analysis.cross_file_refs';

// The rename as a plan (see background.uc), one item per importing file.
export function renamePlan(uri, doc, position, newName) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	// An export alias has no references here; its file's entry has them.
	let nodes = referencesOf(root, doc.text, offset);
	let identity = resolveExportIdentity(uri, doc, offset);
	if (!nodes && !identity?.onAlias) return null;

	let edits = map(nodes ?? [], (n) => ({ range: rangeOf(doc.text, doc.lineTable, n), newText: newName }));
	let changes = length(edits) ? { [uri]: edits } : {};
	if (!identity)
		return { items: [], work: null, finish: () => ({ changes }) };

	let search = crossFileSearch(identity, uri, true);
	return {
		items:  search.items,
		work:   searchEntry,
		finish: (entries) => {
			// A file reached through two modules gets each edit once.
			let seen = {};
			for (let e in edits) seen[sprintf('%s %J', uri, e.range)] = true;
			for (let cr in [search.decl, ...entries]) {
				if (!cr) continue;
				for (let r in cr.renameRanges) {
					let k = sprintf('%s %J', cr.uri, r);
					if (seen[k]) continue;
					seen[k] = true;
					push(changes[cr.uri] ??= [], { range: r, newText: newName });
				}
			}
			return { changes };
		},
	};
};

export function rename(uri, doc, position, newName) {
	let p = renamePlan(uri, doc, position, newName);
	return p ? p.finish(map(p.items, p.work)) : null;
};
