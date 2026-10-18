import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { positionToOffset, rangeOf, findAncestor } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf, anchorOf } from 'ucode_analyzer.code_analysis.scope_references';
import * as mode from 'ucode_analyzer.code_analysis.mode';

// Locate the import_specifier for `remoteName` imported from `specifier` and
// return both of its nodes in a single statement scan:
//   localNode  — the local binding: `bar` for `import { foo as bar }`, else the
//                `foo` node itself (local = remote).
//   remoteNode — the remote-name node, non-null only for an aliased specifier
//                (`import { foo as bar }`); null when local = remote.
// Matches the specifier by remote name first so a mixed list like
// `import { a, foo as bar }` resolves `foo` correctly rather than bailing on the
// first non-aliased entry.
function importSpecNodes(root, text, specifier, remoteName) {
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		if (mode.importStmtSpecifier(stmt, text) !== specifier) continue;
		for (let s in mode.importBindings(stmt).specifiers) {
			if (!s.remoteNode || mode.importRemoteName(s, text) !== remoteName) continue;
			// Aliased when the local binding is a different node than the remote name.
			let aliased = ts.startByte(s.localNode) !== ts.startByte(s.remoteNode);
			return { localNode: s.localNode, remoteNode: aliased ? s.remoteNode : null };
		}
	}
	return { localNode: null, remoteNode: null };
}

// The property nodes (the `bar`) of the `alias.bar` member expressions whose
// `alias` means the namespace import of `specifier`, not a local of that name.
function memberPropertyNodesOf(root, text, specifier, memberName) {
	let result = [];
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement' || mode.importStmtSpecifier(stmt, text) !== specifier)
			continue;
		let ns = mode.importBindings(stmt).namespaceAlias;
		if (!ns) continue;
		for (let use in (referencesOf(root, text, ts.startByte(ns)) ?? [])) {
			let member = ts.parent(use);
			if (!member || ts.nodeType(member) !== 'member_expression') continue;
			let obj  = ts.childByField(member, 'object');
			let prop = ts.childByField(member, 'property');
			if (obj && prop && ts.startByte(obj) === ts.startByte(use) && ts.text(prop, text) === memberName)
				push(result, prop);
		}
	}
	return result;
}

// The `b` nodes of the export specifiers `export { a as b }` that export a
// local under the different name `exportName`.
function exportAliasNodes(root, text, exportName) {
	let out = [];
	for (let spec in ts.descendants(root, ['export_specifier'])) {
		let alias = ts.childByField(spec, 'alias');
		let name  = ts.childByField(spec, 'name');
		if (alias && name && ts.text(alias, text) === exportName && ts.text(name, text) !== exportName)
			push(out, alias);
	}
	return out;
}

// The `b` of an `export { a as b }` the offset is on, or null.
export function exportAliasAt(root, offset) {
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'export_statement' || offset < ts.startByte(stmt) || offset >= ts.endByte(stmt))
			continue;
		let clause = ts.childByField(stmt, 'clause');
		for (let spec in (clause ? ts.namedChildren(clause) : [])) {
			let alias = ts.nodeType(spec) === 'export_specifier' ? ts.childByField(spec, 'alias') : null;
			if (alias && ts.nodeType(alias) === 'identifier' &&
			    ts.startByte(alias) <= offset && offset < ts.endByte(alias))
				return alias;
		}
	}
	return null;
};

// True when uri's module exports name to an import: a legacy return-object
// field is reachable through require() only.
function exported(uri, name) {
	for (let exp in (dag.exportsOf(uri) ?? []))
		if (exp.name === name && !exp.legacy) return true;
	return false;
}

// Convert tree-sitter nodes to `[{ start, end }]` LSP ranges.
function nodeRanges(nodes, text, lineTable) {
	return map(nodes, (n) => rangeOf(text, lineTable, n));
}

// Whether (uri, doc, cursorOffset) refers to an exported symbol: null, or
// { declaringUri, exportName, rename, onAlias }.
//   rename  — a rename follows it to the importers: false on the `a` of
//             `export { a as b }` or the `b` of `import { a as b }`, whose
//             rename leaves the export's name
//   onAlias — the cursor is on that `b`, which has no references of its own
//
// The cursor is on an export alias, on a named import binding or its uses
// (traced to the module that exports it), or on an export of this file or
// its uses.
export function resolveExportIdentity(uri, doc, cursorOffset) {
	let root = ts.rootNode(doc.tree);
	let alias = exportAliasAt(root, cursorOffset);
	if (alias) {
		let name = ts.text(alias, doc.text);
		return exported(uri, name) ? { declaringUri: uri, exportName: name, rename: true, onAlias: true } : null;
	}

	let info = anchorOf(root, doc.text, cursorOffset);
	if (!info || info.anchorByte < 0) return null;

	let targetName = info.targetName;
	let anchorByte = info.anchorByte;
	let anchorNode = info.anchorNode;

	// On an aliased import (`import { foo as bar }`) the cursor is on bar,
	// whose rename only affects this file.
	if (anchorNode && findAncestor(anchorNode, 'import_statement')) {
		for (let imp in (dag.importsOf(uri) ?? [])) {
			if (!imp.resolvedUri || imp.alias !== null) continue;
			if (index(imp.symbols, targetName) < 0) continue;
			let remoteName = (imp.renames && imp.renames[targetName]) ?? targetName;
			if (!exported(imp.resolvedUri, remoteName)) return null;
			return { declaringUri: imp.resolvedUri, exportName: remoteName,
			         rename: remoteName === targetName, onAlias: false };
		}
		return null;
	}

	// An export of this file declared at the anchor: under its own name, else
	// under an alias.
	let aliased = null;
	for (let exp in (dag.exportsOf(uri) ?? [])) {
		if (!exp.position || anchorByte !== positionToOffset(doc.text, doc.lineTable, exp.position)) continue;
		if (exp.name === targetName) return { declaringUri: uri, exportName: exp.name, rename: true, onAlias: false };
		aliased ??= exp.name;
	}
	return aliased ? { declaringUri: uri, exportName: aliased, rename: false, onAlias: false } : null;
};

// Cross-file references come as one entry per file, { uri, refRanges,
// renameRanges }:
//   refRanges    — ranges to include in textDocument/references results
//   renameRanges — ranges to produce rename edits for in textDocument/rename

function entryOf(uri, refRanges, renameRanges) {
	return { uri, refRanges, renameRanges };
}

// The declaring file's entry for the export, or null when it has no
// references or is excludeUri (the caller's file, whose within-file refs are
// already handled).
export function declaringEntry(declaringUri, exportName, excludeUri) {
	if (declaringUri === excludeUri) return null;
	let doc = documents.getOrRead(declaringUri);
	if (!doc) return null;
	let root = ts.rootNode(doc.tree);
	let lt = doc.lineTable;
	for (let exp in (dag.exportsOf(declaringUri) ?? [])) {
		if (exp.name !== exportName) continue;
		// `export { a as b }`: renaming b renames the alias, not the local a.
		let aliases = nodeRanges(exportAliasNodes(root, doc.text, exportName), doc.text, lt);
		// An imported a has no declaration here: its uses are the importer's.
		if (!exp.position) return length(aliases) ? entryOf(declaringUri, [], aliases) : null;
		let byteOff = positionToOffset(doc.text, lt, exp.position);
		let nodes = referencesOf(root, doc.text, byteOff);
		if (!nodes || length(nodes) === 0) return null;
		let ranges = nodeRanges(nodes, doc.text, lt);
		return entryOf(declaringUri, ranges, length(aliases) ? aliases : ranges);
	}
	return null;
};

// The files importing the declaring file, other than excludeUri.
export function importersOf(declaringUri, excludeUri) {
	return filter(dag.reverseDeps(declaringUri), (u) => u !== excludeUri && u !== declaringUri);
};

// An importing file's entry for the export, or null when it cannot be read
// or imports no binding of it. Plain data, so a worker can compute it.
export function importerEntry(revUri, declaringUri, exportName) {
	let doc = documents.getOrRead(revUri);
	if (!doc) return null;
	let root = ts.rootNode(doc.tree);
	let lt = doc.lineTable;
	let e = entryOf(revUri, [], []);
	let matched = false;

	for (let imp in (dag.importsOf(revUri) ?? [])) {
		if (imp.resolvedUri !== declaringUri) continue;

		let refRanges = [];
		let renameRanges = [];

		if (imp.alias !== null) {
			// Namespace import: find `imp.alias.exportName` property accesses.
			let propNodes = memberPropertyNodesOf(root, doc.text, imp.specifier, exportName);
			let ranges = nodeRanges(propNodes, doc.text, lt);
			refRanges = ranges;
			renameRanges = ranges;
		} else {
			// Named import: resolve the local alias for exportName.
			let localName = exportName;
			for (let local, remote in (imp.renames ?? {})) {
				if (remote === exportName) { localName = local; break; }
			}
			if (index(imp.symbols, localName) < 0) continue;

			let sn = importSpecNodes(root, doc.text, imp.specifier, exportName);
			if (!sn.localNode) continue;

			let allNodes = referencesOf(root, doc.text, ts.startByte(sn.localNode));
			if (!allNodes) continue;

			refRanges = nodeRanges(allNodes, doc.text, lt);

			if (localName !== exportName) {
				// Aliased (`{ foo as bar }`): only the remote name in the import
				// specifier changes on rename; local uses of `bar` are unaffected.
				renameRanges = sn.remoteNode ? nodeRanges([sn.remoteNode], doc.text, lt) : [];
			} else {
				renameRanges = refRanges;
			}
		}

		matched = true;
		push(e.refRanges, ...refRanges);
		push(e.renameRanges, ...renameRanges);
	}
	return matched ? e : null;
};

// The local name importerUri binds to uri's export `name` (`*` for a
// namespace import), or null.
function boundName(imp, uri, name) {
	if (imp.resolvedUri !== uri) return null;
	if (imp.alias !== null) return imp.alias;
	for (let local in imp.symbols)
		if (((imp.renames ?? {})[local] ?? local) === name) return local;
	return null;
}

// The exports of importerUri that re-export uri's export `name`:
// [{ uri, name, rename }]. rename is whether they are the same binding, so a
// rename follows: `import { t }; export { t }` is, `export const u = t`,
// `export const t = m.t` and `import { t as u }; export { u }` are not.
function reexportsOf(importerUri, uri, name) {
	let out = [];
	let exps = dag.exportsOf(importerUri) ?? [];
	for (let imp in (dag.importsOf(importerUri) ?? [])) {
		let local = boundName(imp, uri, name);
		if (local === null) continue;
		for (let e in exps) {
			let hit = (imp.alias !== null)
				? (e.memberRef?.alias === local && e.memberRef.member === name)
				: (e.localRef === local || e.local === local);
			if (hit) push(out, { uri: importerUri, name: e.name, rename: e.local === name && e.name === name });
		}
	}
	return out;
}

// The export that uri's `name` re-exports, as reexportsOf describes it, or null.
function reexportedFrom(uri, name) {
	let e = null;
	for (let x in (dag.exportsOf(uri) ?? [])) if (x.name === name) { e = x; break; }
	if (!e) return null;
	let local = e.localRef ?? e.local;
	for (let imp in (dag.importsOf(uri) ?? [])) {
		if (!imp.resolvedUri) continue;
		if (imp.alias !== null) {
			if (e.memberRef?.alias === imp.alias)
				return { uri: imp.resolvedUri, name: e.memberRef.member, rename: false };
		} else if (local !== null && index(imp.symbols, local) >= 0) {
			let remote = (imp.renames ?? {})[local] ?? local;
			return { uri: imp.resolvedUri, name: remote, rename: e.local === remote && e.name === remote };
		}
	}
	return null;
}

function key(uri, name) {
	return uri + '\x00' + name;
}

// The search for the references to `identity` (resolveExportIdentity) outside
// excludeUri's binding of it: { origin, decl, items }, origin the export
// { uri, name } it starts from, decl that file's entry and items
// [importerUri, uri, name] for importerEntry. It follows the
// re-exports up to the declaring module and down to their importers, for a
// rename only those of the same binding.
export function crossFileSearch(identity, excludeUri, forRename) {
	if (forRename && !identity.rename) return { origin: null, decl: null, items: [] };
	// On an export alias the file's own ranges come from its entries.
	if (identity.onAlias) excludeUri = null;

	let origin = { uri: identity.declaringUri, name: identity.exportName };
	let climbed = { [key(origin.uri, origin.name)]: true };
	for (;;) {
		let up = reexportedFrom(origin.uri, origin.name);
		if (!up || (forRename && !up.rename) || climbed[key(up.uri, up.name)]) break;
		climbed[key(up.uri, up.name)] = true;
		origin = { uri: up.uri, name: up.name };
	}
	let seen = { [key(origin.uri, origin.name)]: true };

	// The origin's other names, `export { a, a as b }`, are importers' names
	// for it too, but a rename keeps them.
	let targets = [ { uri: origin.uri, name: origin.name, rename: true } ];
	let exps = dag.exportsOf(origin.uri) ?? [];
	let pos = null;
	for (let e in exps) if (e.name === origin.name) pos = e.position;
	if (pos && !forRename)
		for (let e in exps)
			if (e.name !== origin.name && e.position &&
			    e.position.line === pos.line && e.position.character === pos.character) {
				seen[key(origin.uri, e.name)] = true;
				push(targets, { uri: origin.uri, name: e.name, rename: false });
			}

	for (let i = 0; i < length(targets); i++) {
		let t = targets[i];
		for (let u in dag.reverseDeps(t.uri))
			for (let r in reexportsOf(u, t.uri, t.name)) {
				let rename = t.rename && r.rename;
				if ((forRename && !rename) || seen[key(r.uri, r.name)]) continue;
				seen[key(r.uri, r.name)] = true;
				push(targets, { uri: r.uri, name: r.name, rename });
			}
	}

	let items = [];
	for (let t in targets)
		for (let u in importersOf(t.uri, excludeUri)) push(items, [ u, t.uri, t.name ]);
	return { origin, decl: declaringEntry(origin.uri, origin.name, excludeUri), items };
};

// The entry of a crossFileSearch item.
export function searchEntry(item) {
	return importerEntry(item[0], item[1], item[2]);
};

// Every file's entry for (declaringUri, exportName) but excludeUri's: the
// declaring file's, then its importers', through re-exports.
export function crossFileRefsOf(declaringUri, exportName, excludeUri) {
	let s = crossFileSearch({ declaringUri, exportName, rename: true, onAlias: false }, excludeUri, false);
	return filter([ s.decl, ...map(s.items, searchEntry) ], (e) => e !== null);
};
