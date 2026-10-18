import * as ts from 'tree_sitter';
import * as fs from 'fs';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { positionToOffset, rangeOf, nodeAtOffset, findAncestor } from 'ucode_analyzer.code_analysis.positions';
import { referencesOf, anchorOf } from 'ucode_analyzer.code_analysis.scope_references';
import { resolveExportIdentity, declaringEntry, importersOf, importerEntry } from 'ucode_analyzer.code_analysis.cross_file_refs';
import { SymbolKind } from 'ucode_analyzer.code_analysis.lsp_types';
import { declarators } from 'ucode_analyzer.code_analysis.ast_text';


// ── Utilities ──────────────────────────────────────────────────────────────


// True when refNode is what a call_expression calls: an identifier `f()`, or the
// property of a namespace member `ns.f()`.
function isCallSite(refNode) {
	let callee = refNode;
	let parent = ts.parent(callee);
	if (parent && ts.nodeType(parent) === 'member_expression') {
		let prop = ts.childByField(parent, 'property');
		if (!prop || ts.startByte(prop) !== ts.startByte(refNode)) return false;
		callee = parent;
		parent = ts.parent(callee);
	}
	if (!parent || ts.nodeType(parent) !== 'call_expression') return false;
	let fn = ts.childByField(parent, 'function');
	return fn && ts.startByte(fn) === ts.startByte(callee) && ts.endByte(fn) === ts.endByte(callee);
}

function isFunctionNode(node) {
	let t = node ? ts.nodeType(node) : null;
	return t === 'function_declaration' || t === 'function_expression' || t === 'arrow_function';
}

// ── CallHierarchyItem builders ─────────────────────────────────────────────

// Build an item for a named function declaration or function-valued variable.
function makeItem(name, fnNode, nameNode, uri, text, lineTable) {
	let fnRange   = rangeOf(text, lineTable, fnNode);
	let nameRange = nameNode
		? rangeOf(text, lineTable, nameNode)
		: fnRange;
	return {
		name,
		kind: SymbolKind.FUNCTION,
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
	return {
		name: fs.basename(uri),
		kind: SymbolKind.MODULE,   // a call site outside any function
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
			let nameNode = ts.childByField(n, 'name');
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
			let nm = ts.childByField(node, 'name');
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

// The function a named import binds in callerUri: { fnNode, nameNode, uri, doc },
// or null.
function importedCallee(name, callerUri) {
	for (let imp in (dag.importsOf(callerUri) ?? [])) {
		if (!imp.resolvedUri || imp.alias !== null) continue;
		if (index(imp.symbols, name) < 0) continue;
		let remoteName = (imp.renames && imp.renames[name]) ?? name;
		let exp = dag.resolveExport(imp.resolvedUri, remoteName);
		if (!exp || !exp.position) continue;
		let doc = documents.getOrRead(imp.resolvedUri);
		if (!doc) continue;
		let byteOff = positionToOffset(doc.text, doc.lineTable, exp.position);
		let r = findFnAt(ts.rootNode(doc.tree), doc.text, byteOff);
		if (r && isFunctionNode(r.fnNode)) return { fnNode: r.fnNode, nameNode: r.nameNode, uri: imp.resolvedUri, doc };
	}
	return null;
}

// The top-level function named `name` in the file, or null: a function may
// call one declared after it, which has run by the time it is called.
function topLevelCallee(name, callerUri, callerDoc) {
	let text = callerDoc.text;
	for (let stmt in ts.namedChildren(ts.rootNode(callerDoc.tree))) {
		let inner = (ts.nodeType(stmt) === 'export_statement') ? ts.childByField(stmt, 'declaration') : stmt;
		let nt = inner ? ts.nodeType(inner) : null;
		if (nt === 'function_declaration') {
			let nm = ts.childByField(inner, 'name');
			if (nm && ts.nodeType(nm) === 'identifier' && ts.text(nm, text) === name)
				return { fnNode: inner, nameNode: nm, uri: callerUri, doc: callerDoc };
		} else if (nt === 'lexical_declaration') {
			for (let vd in declarators(inner)) {
				let nm = ts.childByField(vd, 'name');
				let val = ts.childByField(vd, 'value');
				if (nm && ts.text(nm, text) === name && isFunctionNode(val))
					return { fnNode: val, nameNode: nm, uri: callerUri, doc: callerDoc };
			}
		}
	}
	return null;
}

// The function an identifier callee means, as { fnNode, nameNode, uri, doc },
// or null: the declaration in scope (a nested function, a named import), else
// a later top-level function. A parameter or another value calls nothing known.
function resolveCalleeIdent(identNode, callerUri, callerDoc) {
	let name = ts.text(identNode, callerDoc.text);
	let root = ts.rootNode(callerDoc.tree);
	let anchor = anchorOf(root, callerDoc.text, ts.startByte(identNode));
	if (!anchor || anchor.anchorByte < 0 || !anchor.anchorNode)
		return topLevelCallee(name, callerUri, callerDoc);
	if (findAncestor(anchor.anchorNode, 'import_statement'))
		return importedCallee(name, callerUri);
	let r = findFnAt(root, callerDoc.text, anchor.anchorByte);
	return (r && isFunctionNode(r.fnNode))
		? { fnNode: r.fnNode, nameNode: r.nameNode, uri: callerUri, doc: callerDoc } : null;
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
		let nameChild = ts.childByField(parent, 'name');
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
		let first = ts.childByField(refParent, 'name');
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
			let declDoc = documents.getOrRead(loc.uri);
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

	// An aliased import (`import { greet as hi }`) has no export identity, which
	// keeps rename local; it still calls the function it imports.
	let callee = resolveCalleeIdent(node, uri, doc);
	if (callee && callee.uri !== uri)
		return [makeItem(ts.text(callee.nameNode, callee.doc.text), callee.fnNode, callee.nameNode,
		                 callee.uri, callee.doc.text, callee.doc.lineTable)];
	return null;
};

// The call sites among a file's reference nodes, grouped by caller in
// first-seen order: [{ key, from, fromRanges }].
function callersIn(refNodes, refUri, refDoc) {
	let byKey = {}, out = [];
	for (let refNode in refNodes) {
		if (!isCallSite(refNode)) continue;
		let caller = enclosingItem(refNode, refUri, refDoc.text, refDoc.lineTable);
		let key    = sprintf('%s:%d:%d', caller.uri, caller.range.start.line, caller.range.start.character);
		if (!byKey[key]) push(out, byKey[key] = { key, from: caller, fromRanges: [] });
		push(byKey[key].fromRanges, rangeOf(refDoc.text, refDoc.lineTable, refNode));
	}
	return out;
}

// The callers in a cross-file entry's file. Its ranges already enumerate every
// reference there, so each maps straight to its node.
function entryCallers(cr) {
	let refDoc = cr ? documents.getOrRead(cr.uri) : null;
	if (!refDoc) return [];
	let refRoot = ts.rootNode(refDoc.tree);
	let nodes = [];
	for (let rng in cr.refRanges) {
		let node = nodeAtOffset(refRoot, positionToOffset(refDoc.text, refDoc.lineTable, rng.start));
		if (node) push(nodes, node);
	}
	return callersIn(nodes, cr.uri, refDoc);
}

// Per-file caller lists merged by caller, or null when there are none.
function mergeCallers(lists) {
	let byKey = {}, out = [];
	for (let list in lists)
		for (let c in (list ?? [])) {
			if (byKey[c.key]) {
				push(byKey[c.key].fromRanges, ...c.fromRanges);
				continue;
			}
			push(out, byKey[c.key] = { from: c.from, fromRanges: [...c.fromRanges] });
		}
	return length(out) > 0 ? out : null;
}

// The incoming calls of item (the functions that call it) as a plan (see
// background.uc), one item per importing file.
export function incomingCallsPlan(item) {
	let uri            = item.data.uri;
	let nameByteOffset = item.data.nameByteOffset;
	let doc = documents.getOrRead(uri);
	if (!doc) return null;

	let root  = ts.rootNode(doc.tree);
	let local = callersIn(referencesOf(root, doc.text, nameByteOffset, false) ?? [], uri, doc);

	let identity = resolveExportIdentity(uri, doc, nameByteOffset);
	if (!identity)
		return { items: [], work: null, finish: () => mergeCallers([local]) };

	let decl = entryCallers(declaringEntry(identity.declaringUri, identity.exportName, uri));
	return {
		items:  importersOf(identity.declaringUri, uri),
		work:   (u) => entryCallers(importerEntry(u, identity.declaringUri, identity.exportName)),
		finish: (lists) => mergeCallers([local, decl, ...lists]),
	};
};

export function incomingCalls(item) {
	let p = incomingCallsPlan(item);
	return p ? p.finish(map(p.items, p.work)) : null;
};

// Return all outgoing calls from item (functions this function calls).
export function outgoingCalls(item) {
	let uri            = item.data.uri;
	let nameByteOffset = item.data.nameByteOffset;
	let doc = documents.getOrRead(uri);
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
			let fromRange = rangeOf(doc.text, doc.lineTable, callee);
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
		let fromRange = rangeOf(doc.text, doc.lineTable, callee);
		let entry = { to: calleeItem, fromRanges: [fromRange] };
		seen[key] = entry;
		push(result, entry);
	}

	return length(result) > 0 ? result : null;
};
