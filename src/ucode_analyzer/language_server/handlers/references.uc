import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { positionToOffset, rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf } from 'ucode_analyzer.code_analysis.scope_references';
import { resolveExportIdentity, crossFileSearch, searchEntry } from 'ucode_analyzer.code_analysis.cross_file_refs';

// The references as a plan (see background.uc), one item per importing file.
export function referencesPlan(uri, doc, position, includeDeclaration) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	// An export alias has no references here; its file's entry has them.
	let nodes = referencesOf(root, doc.text, offset, includeDeclaration);
	let identity = resolveExportIdentity(uri, doc, offset);
	if (!nodes && !identity?.onAlias) return null;

	let result = map(nodes ?? [], (n) => ({ uri, range: rangeOf(doc.text, doc.lineTable, n) }));
	if (!identity)
		return { items: [], work: null, finish: () => result };

	// The cross-file entries include the export's own declaration (in the
	// declaring module) when the cursor is in an importing file. Honor
	// includeDeclaration:false by dropping that one range.
	let search = crossFileSearch(identity, uri, false);
	let declPos = null;
	if (includeDeclaration === false) {
		let loc = dag.resolveExportLocation(search.origin.uri, search.origin.name);
		let exp = dag.resolveExport(loc.uri, loc.name);
		if (exp && exp.position) declPos = { uri: loc.uri, position: exp.position };
	}

	return {
		items:  search.items,
		work:   searchEntry,
		finish: (entries) => {
			for (let cr in [search.decl, ...entries]) {
				if (!cr) continue;
				for (let range in cr.refRanges) {
					if (declPos && cr.uri === declPos.uri &&
					    range.start.line === declPos.position.line &&
					    range.start.character === declPos.position.character)
						continue;
					push(result, { uri: cr.uri, range });
				}
			}
			return result;
		},
	};
};

export function references(uri, doc, position, includeDeclaration) {
	let p = referencesPlan(uri, doc, position, includeDeclaration);
	return p ? p.finish(map(p.items, p.work)) : null;
};
