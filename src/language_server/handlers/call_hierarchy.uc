import * as ts from 'tree_sitter';
import * as fs from 'fs';
import * as documents from 'code_analysis.documents';
import * as dag from 'code_analysis.dag.dag';
import { positionToOffset, offsetToPosition, buildLineTable, nodeAtOffset } from 'code_analysis.positions';
import { referencesOf } from 'language_server.scope_references';
import { resolveExportIdentity, crossFileRefsOf } from 'language_server.cross_file_refs';
import * as mode from 'code_analysis.mode';

let KIND_FUNCTION = 12;
let KIND_MODULE   = 2;  // used for module-level call sites (no enclosing function)

// ── Utilities ──────────────────────────────────────────────────────────────

function loadDoc(uri) {
	let doc = documents.get(uri);
	if (doc) return doc;
	let path = substr(uri, 7);
	let text = fs.readfile(path);
	if (!text) return null;
	return { uri, text, tree: mode.parse(text), lineTable: buildLineTable(text) };
}

function rangeOf(text, lineTable, startByte, endByte) {
	return {
		start: offsetToPosition(text, lineTable, startByte),
		end:   offsetToPosition(text, lineTable, endByte),
	};
}

// True when refNode (an identifier) is the direct callee of a call_expression.
function isCallSite(refNode) {
	let parent = ts.parent(refNode);
	if (!parent || ts.nodeType(parent) !== 'call_expression') return false;
	let fn = ts.childByField(parent, 'function');
	return fn && ts.startByte(fn) === ts.startByte(refNode);
}

// ── CallHierarchyItem builders ─────────────────────────────────────────────

// Build an item for a named function declaration or function-valued variable.
function makeItem(name, fnNode, nameNode, uri, text, lineTable) {
	let fnRange   = rangeOf(text, lineTable, ts.startByte(fnNode), ts.endByte(fnNode));
	let nameRange = nameNode
		? rangeOf(text, lineTable, ts.startByte(nameNode), ts.endByte(nameNode))
		: fnRange;
	return {
		name,
		kind: KIND_FUNCTION,
		uri,
		range: fnRange,
		selectionRange: nameRange,
		data: {
			uri,
			nameByteOffset: nameNode ? ts.startByte(nameNode) : ts.startByte(fnNode),
		},
	};
}

// Fallback item for callers at module level (not inside any function).
function moduleItem(uri) {
	let name = uri;
	let slash = rindex(uri, '/');
	if (slash >= 0) name = substr(uri, slash + 1);
	return {
		name,
		kind: KIND_MODULE,
		uri,
		range:          { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
		selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
		data: { uri, nameByteOffset: -1 },
	};
}

// ── AST helpers ────────────────────────────────────────────────────────────

// Walk up to the nearest enclosing function and return a CallHierarchyItem for it.
// Returns a module-level item when no enclosing function exists.
function enclosingItem(node, uri, text, lineTable) {
	let n = ts.parent(node);
	while (n) {
		let nt = ts.nodeType(n);
		if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(n, 0);
			let name = (nameNode && ts.nodeType(nameNode) === 'identifier')
				? ts.text(nameNode, text) : '(anonymous)';
			return makeItem(name, n, nameNode, uri, text, lineTable);
		}
		if (nt === 'function_expression' || nt === 'arrow_function') {
			// Try to recover the variable name from a `let f = function() {}` pattern.
			let vd     = ts.parent(n);
			let nameNode = (vd && ts.nodeType(vd) === 'variable_declarator')
				? ts.childByField(vd, 'name') : null;
			let name = nameNode ? ts.text(nameNode, text) : '(anonymous)';
			let fnNode = nameNode ? (ts.parent(vd) ?? n) : n;
			return makeItem(name, fnNode, nameNode, uri, text, lineTable);
		}
		n = ts.parent(n);
	}
	return moduleItem(uri);
}

// Given a function name identifier at nameByteOffset, find the function node.
// Returns { fnNode, nameNode } or null.
function findFnAt(root, text, nameByteOffset) {
	function scan(node) {
		let nt = ts.nodeType(node);
		if (nt === 'function_declaration') {
			let nm = ts.namedChild(node, 0);
			if (nm && ts.nodeType(nm) === 'identifier' && ts.startByte(nm) === nameByteOffset)
				return { fnNode: node, nameNode: nm };
		}
		if (nt === 'variable_declarator') {
			let nm = ts.childByField(node, 'name');
			if (nm && ts.startByte(nm) === nameByteOffset) {
				let val = ts.childByField(node, 'value');
				return val ? { fnNode: val, nameNode: nm } : null;
			}
		}
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let r = scan(ts.namedChild(node, i));
			if (r) return r;
		}
		return null;
	}
	return scan(root);
}

// Collect all call_expression nodes inside fnNode (not crossing nested function
// boundaries, since those are tracked by their own outgoingCalls call).
function collectCallsIn(fnNode, out) {
	function walk(node) {
		let nt = ts.nodeType(node);
		if (nt === 'call_expression') {
			push(out, node);
			// Still recurse into arguments (nested calls), but skip nested function bodies.
			let args = ts.childByField(node, 'arguments');
			if (args) walk(args);
			return;
		}
		// Don't descend into nested function bodies — their calls belong to their own item.
		if (nt === 'function_declaration' || nt === 'function_expression' || nt === 'arrow_function')
			return;
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i));
	}
	let body = ts.childByField(fnNode, 'body');
	if (body) walk(body);
}

// Try to resolve a simple identifier callee to a { fnNode, nameNode, uri, doc }.
// Handles locally-declared functions and named imports; skips member calls.
function resolveCalleeIdent(identNode, callerUri, callerDoc) {
	let name = ts.text(identNode, callerDoc.text);

	// Named import → declaration in the exporting file.
	for (let imp in (dag.importsOf(callerUri) ?? [])) {
		if (!imp.resolvedUri || imp.alias !== null) continue;
		if (index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let exp = dag.resolveExport(imp.resolvedUri, remoteName);
		if (!exp || !exp.position) continue;
		let doc = loadDoc(imp.resolvedUri);
		if (!doc) continue;
		let byteOff = positionToOffset(doc.text, doc.lineTable, exp.position);
		let r = findFnAt(ts.rootNode(doc.tree), doc.text, byteOff);
		if (r) return { fnNode: r.fnNode, nameNode: r.nameNode, uri: imp.resolvedUri, doc };
	}

	// Local or top-level declaration in the same file.
	let root = ts.rootNode(callerDoc.tree);
	let r = findFnAt(root, callerDoc.text, -999);  // scan all
	// findFnAt only matches on byte offset; for local lookup we need a name scan.
	function scanLocal(node) {
		let nt = ts.nodeType(node);
		if (nt === 'function_declaration' || (nt === 'export_statement' && ts.namedChildCount(node) > 0)) {
			let inner = (nt === 'export_statement') ? ts.namedChild(node, 0) : node;
			if (!inner) return null;
			let nm = ts.namedChild(inner, 0);
			if (nm && ts.nodeType(nm) === 'identifier' && ts.text(nm, callerDoc.text) === name)
				return { fnNode: inner, nameNode: nm, uri: callerUri, doc: callerDoc };
		}
		if (nt === 'lexical_declaration' || (nt === 'export_statement' && ts.namedChildCount(node) > 0)) {
			let inner = (nt === 'export_statement') ? ts.namedChild(node, 0) : node;
			if (!inner || ts.nodeType(inner) !== 'lexical_declaration') return null;
			for (let i = 0; i < ts.namedChildCount(inner); i++) {
				let vd = ts.namedChild(inner, i);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nm = ts.childByField(vd, 'name');
				if (!nm || ts.text(nm, callerDoc.text) !== name) continue;
				let val = ts.childByField(vd, 'value');
				let vnt = val ? ts.nodeType(val) : null;
				if (vnt === 'function_expression' || vnt === 'arrow_function')
					return { fnNode: val, nameNode: nm, uri: callerUri, doc: callerDoc };
			}
		}
		return null;
	}
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let found = scanLocal(ts.namedChild(root, i));
		if (found) return found;
	}

	return null;
}

// ── Exported handlers ──────────────────────────────────────────────────────

// Return a CallHierarchyItem for the function under the cursor, or null.
export function prepareCallHierarchy(uri, doc, position) {
	let offset = positionToOffset(doc.text, doc.lineTable, position);
	let root   = ts.rootNode(doc.tree);
	if (offset >= ts.endByte(root)) return null;

	let node = nodeAtOffset(root, offset);
	if (!node || ts.nodeType(node) !== 'identifier') return null;

	let name   = ts.text(node, doc.text);
	let parent = ts.parent(node);
	if (!parent) return null;
	let pnt = ts.nodeType(parent);

	// Cursor on a function declaration name.
	if (pnt === 'function_declaration') {
		let nameChild = ts.namedChild(parent, 0);
		if (!nameChild || ts.startByte(nameChild) !== ts.startByte(node)) return null;
		return [makeItem(name, parent, node, uri, doc.text, doc.lineTable)];
	}

	// Cursor on a variable declarator holding a function expression or arrow.
	if (pnt === 'variable_declarator') {
		let nm = ts.childByField(parent, 'name');
		if (!nm || ts.startByte(nm) !== ts.startByte(node)) return null;
		let val = ts.childByField(parent, 'value');
		let vnt = val ? ts.nodeType(val) : null;
		if (vnt !== 'function_expression' && vnt !== 'arrow_function') return null;
		let declNode = ts.parent(parent) ?? parent;
		return [makeItem(name, declNode, node, uri, doc.text, doc.lineTable)];
	}

	// Cursor on a call site or reference — resolve to definition and return its item.
	let refNodes = referencesOf(root, doc.text, offset, true);
	if (!refNodes || length(refNodes) === 0) return null;

	// Find the declaration node (the one at anchorByte).
	for (let ref in refNodes) {
		let refParent = ts.parent(ref);
		if (!refParent) continue;
		let rpnt = ts.nodeType(refParent);
		let first = ts.namedChild(refParent, 0);
		if (rpnt === 'function_declaration' && first && ts.startByte(first) === ts.startByte(ref))
			return [makeItem(name, refParent, ref, uri, doc.text, doc.lineTable)];
		if (rpnt === 'variable_declarator') {
			let nm = ts.childByField(refParent, 'name');
			if (nm && ts.startByte(nm) === ts.startByte(ref)) {
				let val = ts.childByField(refParent, 'value');
				let vnt = val ? ts.nodeType(val) : null;
				if (vnt === 'function_expression' || vnt === 'arrow_function') {
					let declNode = ts.parent(refParent) ?? refParent;
					return [makeItem(name, declNode, ref, uri, doc.text, doc.lineTable)];
				}
			}
		}
	}

	// Cross-file: the cursor is on an imported name (its use or its import binding),
	// which has no local declaration. Resolve the export to its declaring module
	// and build the item there so the hierarchy anchors on the real function.
	let identity = resolveExportIdentity(uri, doc, offset);
	if (identity) {
		let loc = dag.resolveExportLocation(identity.declaringUri, identity.exportName);
		let exp = dag.resolveExport(loc.uri, loc.name);
		if (exp && exp.position) {
			let declDoc = loadDoc(loc.uri);
			if (declDoc) {
				let declRoot = ts.rootNode(declDoc.tree);
				let byteOff  = positionToOffset(declDoc.text, declDoc.lineTable, exp.position);
				let found    = findFnAt(declRoot, declDoc.text, byteOff);
				if (found) {
					let fnt = ts.nodeType(found.fnNode);
					if (fnt === 'function_declaration' || fnt === 'function_expression' || fnt === 'arrow_function')
						return [makeItem(loc.name, found.fnNode, found.nameNode,
						                 loc.uri, declDoc.text, declDoc.lineTable)];
				}
			}
		}
	}
	return null;
};

// Return all incoming call sites for item (functions that call this function).
export function incomingCalls(item) {
	let uri            = item.data.uri;
	let nameByteOffset = item.data.nameByteOffset;
	let doc = loadDoc(uri);
	if (!doc) return null;

	// Collect { callerItem, fromRange } pairs, keyed by callerItem range to deduplicate.
	let callerMap = {};

	function addCallSite(refNode, refUri, refDoc) {
		if (!isCallSite(refNode)) return;
		let lt    = refDoc.lineTable;
		let text  = refDoc.text;
		let fnRange = rangeOf(text, lt, ts.startByte(refNode), ts.endByte(refNode));
		let caller  = enclosingItem(refNode, refUri, text, lt);
		let key     = sprintf('%s:%d:%d', caller.uri, caller.range.start.line, caller.range.start.character);
		if (!exists(callerMap, key))
			callerMap[key] = { from: caller, fromRanges: [] };
		push(callerMap[key].fromRanges, fnRange);
	}

	// Within-file references.
	let root     = ts.rootNode(doc.tree);
	let refNodes = referencesOf(root, doc.text, nameByteOffset, false);
	for (let ref in (refNodes ?? []))
		addCallSite(ref, uri, doc);

	// Cross-file references via the export identity.
	let identity = resolveExportIdentity(uri, doc, nameByteOffset);
	if (identity) {
		for (let cr in crossFileRefsOf(identity.declaringUri, identity.exportName, uri)) {
			let refDoc = loadDoc(cr.uri);
			if (!refDoc) continue;
			let refRoot = ts.rootNode(refDoc.tree);
			// cr.refRanges already enumerates every reference in this file. Map each
			// straight to its node and add it once — re-running referencesOf per range
			// re-derived the whole set each time (O(refs²)) and pushed every call site
			// once per range (duplicated fromRanges).
			for (let rng in cr.refRanges) {
				let byteOff = positionToOffset(refDoc.text, refDoc.lineTable, rng.start);
				let node    = nodeAtOffset(refRoot, byteOff);
				if (node) addCallSite(node, cr.uri, refDoc);
			}
		}
	}

	let result = [];
	for (let _, entry in callerMap) push(result, entry);
	return length(result) > 0 ? result : null;
};

// Return all outgoing calls from item (functions this function calls).
export function outgoingCalls(item) {
	let uri            = item.data.uri;
	let nameByteOffset = item.data.nameByteOffset;
	let doc = loadDoc(uri);
	if (!doc) return null;

	let root = ts.rootNode(doc.tree);
	let found = findFnAt(root, doc.text, nameByteOffset);
	if (!found) return null;

	let calls = [];
	collectCallsIn(found.fnNode, calls);

	// Deduplicate callees by their declaration uri+offset.
	let seen    = {};
	let result  = [];

	for (let callNode in calls) {
		let callee = ts.childByField(callNode, 'function');
		if (!callee || ts.nodeType(callee) !== 'identifier') continue;

		let resolved = resolveCalleeIdent(callee, uri, doc);
		if (!resolved) continue;

		let key = sprintf('%s:%d', resolved.uri, ts.startByte(resolved.nameNode ?? resolved.fnNode));
		if (exists(seen, key)) {
			// Already have this callee; just add the from-range.
			let fromRange = rangeOf(doc.text, doc.lineTable,
				ts.startByte(callee), ts.endByte(callee));
			push(seen[key].fromRanges, fromRange);
			continue;
		}

		let calleeItem = makeItem(
			ts.text(resolved.nameNode ?? callee, resolved.doc.text),
			resolved.fnNode,
			resolved.nameNode,
			resolved.uri,
			resolved.doc.text,
			resolved.doc.lineTable
		);
		let fromRange = rangeOf(doc.text, doc.lineTable,
			ts.startByte(callee), ts.endByte(callee));
		let entry = { to: calleeItem, fromRanges: [fromRange] };
		seen[key] = entry;
		push(result, entry);
	}

	return length(result) > 0 ? result : null;
};
