import * as ts from 'tree_sitter';
import * as fs from 'fs';
import * as dag from 'language_server.dag.dag';
import * as documents from 'language_server.documents';
import { positionToOffset, offsetToPosition, buildLineTable } from 'language_server.positions';
import { referencesOf, anchorOf } from 'language_server.scope_references';

let _parser = ts.newParser(ts.ucode());

// Walk up parent chain looking for a node of the given type.
function findAncestor(node, type) {
	let n = ts.parent(node);
	while (n) {
		if (ts.nodeType(n) === type) return n;
		n = ts.parent(n);
	}
	return null;
}

// Extract the module specifier string (without quotes) from an import_statement.
function importStmtSpecifier(stmt, text) {
	for (let i = 0; i < ts.childCount(stmt); i++) {
		let child = ts.child(stmt, i);
		if (ts.nodeType(child) !== 'string') continue;
		for (let j = 0; j < ts.childCount(child); j++) {
			let frag = ts.child(child, j);
			if (ts.nodeType(frag) === 'string_fragment') return ts.text(frag, text);
		}
	}
	return null;
}

// Find the local binding node in an import_statement for a given (specifier, remoteName).
// For `import { foo } from 'spec'`: returns the `foo` node (local = remote).
// For `import { foo as bar } from 'spec'`: returns the `bar` node (local alias).
function importLocalNode(root, text, specifier, remoteName) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		if (importStmtSpecifier(stmt, text) !== specifier) continue;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let clause = ts.child(stmt, j);
			if (ts.nodeType(clause) !== 'import_clause') continue;
			let inner = ts.namedChild(clause, 0);
			if (!inner || ts.nodeType(inner) !== 'named_imports') continue;
			for (let k = 0; k < ts.namedChildCount(inner); k++) {
				let spec = ts.namedChild(inner, k);
				if (ts.nodeType(spec) !== 'import_specifier') continue;
				let remoteNode = ts.namedChild(spec, 0);
				if (!remoteNode || ts.text(remoteNode, text) !== remoteName) continue;
				let count = ts.namedChildCount(spec);
				return ts.namedChild(spec, count - 1);
			}
		}
	}
	return null;
}

// Find the remote-name node in an aliased import: `import { remoteName as local }`.
// Returns null when the import has no alias (remote = local).
function importRemoteNode(root, text, specifier, remoteName) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		if (importStmtSpecifier(stmt, text) !== specifier) continue;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let clause = ts.child(stmt, j);
			if (ts.nodeType(clause) !== 'import_clause') continue;
			let inner = ts.namedChild(clause, 0);
			if (!inner || ts.nodeType(inner) !== 'named_imports') continue;
			for (let k = 0; k < ts.namedChildCount(inner); k++) {
				let spec = ts.namedChild(inner, k);
				if (ts.nodeType(spec) !== 'import_specifier') continue;
				let count = ts.namedChildCount(spec);
				if (count < 2) return null;
				let remoteNode = ts.namedChild(spec, 0);
				if (!remoteNode || ts.text(remoteNode, text) !== remoteName) continue;
				return remoteNode;
			}
		}
	}
	return null;
}

// Find the property identifier nodes (the `bar` part) for `alias.bar` member expressions.
function memberPropertyNodesOf(root, text, alias, memberName) {
	let result = [];
	function scan(node) {
		if (ts.nodeType(node) === 'member_expression') {
			let obj  = ts.childByField(node, 'object');
			let prop = ts.childByField(node, 'property');
			if (obj && prop &&
			    ts.nodeType(obj) === 'identifier' &&
			    ts.text(obj, text) === alias &&
			    ts.text(prop, text) === memberName) {
				push(result, prop);
				return;
			}
		}
		for (let i = 0; i < ts.namedChildCount(node); i++)
			scan(ts.namedChild(node, i));
	}
	scan(root);
	return result;
}

// Load a document from the editor (open files) or from disk.
function loadDoc(uri) {
	let doc = documents.get(uri);
	if (doc) return doc;
	let path = substr(uri, 7);
	let f = fs.open(path, 'r');
	if (!f) return null;
	let text = f.read('all');
	f.close();
	let lineTable = buildLineTable(text);
	return { text, tree: ts.parse(_parser, text), lineTable };
}

// Convert tree-sitter nodes to `[{ start, end }]` LSP ranges.
function nodeRanges(nodes, text, lineTable) {
	return map(nodes, (n) => ({
		start: offsetToPosition(text, lineTable, ts.startByte(n)),
		end:   offsetToPosition(text, lineTable, ts.endByte(n)),
	}));
}

// Determine whether (uri, doc, cursorOffset) refers to an exported symbol.
// Returns { declaringUri, exportName } or null.
//
// Three cases trigger cross-file resolution:
//   1. Cursor is on a non-aliased named import binding — traces to the declaring file.
//   2. Cursor is on any usage (including declaration) of an export in the same file.
export function resolveExportIdentity(uri, doc, cursorOffset) {
	let root = ts.rootNode(doc.tree);
	let info = anchorOf(root, doc.text, cursorOffset);
	if (!info || info.anchorByte < 0) return null;

	let targetName = info.targetName;
	let anchorByte = info.anchorByte;
	let anchorNode = info.anchorNode;

	// Case 1: anchor is inside an import_statement — cursor is on a named import binding.
	// Skip aliased imports (remoteName !== targetName) because then the cursor is on the
	// local alias and renaming should only affect the local file.
	if (anchorNode && findAncestor(anchorNode, 'import_statement')) {
		for (let imp in (dag.importsOf(uri) ?? [])) {
			if (!imp.resolvedUri || imp.alias !== null) continue;
			if (index(imp.symbols, targetName) < 0) continue;
			let remoteName = (imp.renames && imp.renames[targetName]) ?? targetName;
			if (remoteName !== targetName) return null;
			return { declaringUri: imp.resolvedUri, exportName: remoteName };
		}
		return null;
	}

	// Case 2: anchor byte matches the position of an export in this file.
	for (let exp in (dag.exportsOf(uri) ?? [])) {
		if (exp.name !== targetName || !exp.position) continue;
		if (anchorByte === positionToOffset(doc.text, doc.lineTable, exp.position))
			return { declaringUri: uri, exportName: exp.name };
	}

	return null;
};

// Find all cross-file reference ranges for (declaringUri, exportName).
// excludeUri is the caller's file (its within-file refs are already handled).
// Returns [{ uri, refRanges, renameRanges }].
//   refRanges    — ranges to include in textDocument/references results
//   renameRanges — ranges to produce rename edits for in textDocument/rename
export function crossFileRefsOf(declaringUri, exportName, excludeUri) {
	let entries = {};

	function getEntry(uri) {
		if (!entries[uri]) entries[uri] = { uri, refRanges: [], renameRanges: [] };
		return entries[uri];
	}

	// Include the declaring file when the cursor is in an importing file.
	if (declaringUri !== excludeUri) {
		let doc = loadDoc(declaringUri);
		if (doc) {
			let root = ts.rootNode(doc.tree);
			let lt = doc.lineTable;
			for (let exp in (dag.exportsOf(declaringUri) ?? [])) {
				if (exp.name !== exportName || !exp.position) continue;
				let byteOff = positionToOffset(doc.text, lt, exp.position);
				let nodes = referencesOf(root, doc.text, byteOff);
				if (nodes && length(nodes) > 0) {
					let ranges = nodeRanges(nodes, doc.text, lt);
					let e = getEntry(declaringUri);
					for (let r in ranges) { push(e.refRanges, r); push(e.renameRanges, r); }
				}
				break;
			}
		}
	}

	// Importing files.
	for (let revUri in dag.reverseDeps(declaringUri)) {
		if (revUri === excludeUri || revUri === declaringUri) continue;

		let doc = loadDoc(revUri);
		if (!doc) continue;
		let root = ts.rootNode(doc.tree);
		let lt = doc.lineTable;

		for (let imp in (dag.importsOf(revUri) ?? [])) {
			if (imp.resolvedUri !== declaringUri) continue;

			let refRanges = [];
			let renameRanges = [];

			if (imp.alias !== null) {
				// Namespace import: find `imp.alias.exportName` property accesses.
				let propNodes = memberPropertyNodesOf(root, doc.text, imp.alias, exportName);
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

				let localNode = importLocalNode(root, doc.text, imp.specifier, exportName);
				if (!localNode) continue;

				let allNodes = referencesOf(root, doc.text, ts.startByte(localNode));
				if (!allNodes) continue;

				refRanges = nodeRanges(allNodes, doc.text, lt);

				if (localName !== exportName) {
					// Aliased (`{ foo as bar }`): only the remote name in the import
					// specifier changes on rename; local uses of `bar` are unaffected.
					let remoteNode = importRemoteNode(root, doc.text, imp.specifier, exportName);
					renameRanges = remoteNode ? nodeRanges([remoteNode], doc.text, lt) : [];
				} else {
					renameRanges = refRanges;
				}
			}

			let e = getEntry(revUri);
			for (let r in refRanges)    push(e.refRanges, r);
			for (let r in renameRanges) push(e.renameRanges, r);
		}
	}

	let result = [];
	for (let _, entry in entries) push(result, entry);
	return result;
};
