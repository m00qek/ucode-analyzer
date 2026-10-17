import * as ts from 'tree_sitter';
import { eachName, declarationOf } from 'ucode_analyzer.code_analysis.bindings';

// Every identifier named targetName, declaration or use, as { node,
// declOffset }: the start byte of the identifier declaring it (its own for a
// declaration), -1 when undeclared.
function occurrences(root, source, targetName) {
	let out = [];
	eachName(root, source, {
		declare: (node, name) => {
			if (name === targetName) push(out, { node, declOffset: ts.startByte(node) });
		},
		use: (node, name, scope) => {
			// A shorthand `{ x }` uses x too, but renaming it would rename the key.
			if (name === targetName && ts.nodeType(node) === 'identifier')
				push(out, { node, declOffset: declarationOf(scope, name) });
		},
	});
	return out;
}

// Find the deepest identifier node whose byte span contains offset, or null.
function identifierAt(node, offset) {
	if (ts.startByte(node) > offset || offset >= ts.endByte(node)) return null;
	let result = (ts.nodeType(node) === 'identifier') ? node : null;
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let deeper = identifierAt(ts.namedChild(node, i), offset);
		if (deeper) result = deeper;
	}
	return result;
}

// Return the anchor (declaration site) information for the identifier at
// cursorOffset, or null if the offset does not land on an identifier.
// { targetName, anchorByte, anchorNode }:
//   anchorByte  — declaration byte-offset (-1 when the name is unresolved/global)
//   anchorNode  — the identifier ts-node at anchorByte, or null
export function anchorOf(root, source, cursorOffset) {
	let cursorNode = identifierAt(root, cursorOffset);
	if (!cursorNode) return null;
	let targetName = ts.text(cursorNode, source);
	let cursorStart = ts.startByte(cursorNode);
	let all = occurrences(root, source, targetName);
	for (let i = 0; i < length(all); i++) {
		if (ts.startByte(all[i].node) === cursorStart) {
			let anchorByte = all[i].declOffset;
			let anchorNode = (anchorByte >= 0) ? identifierAt(root, anchorByte) : null;
			return { targetName, anchorByte, anchorNode };
		}
	}
	return null;
};

// Return all identifier nodes in the file that refer to the same binding as the
// identifier at cursorOffset.  Identifiers in different scopes that happen to
// share a name are excluded.
//
// Returns null if cursorOffset does not land on an identifier node.
// Returns an array (possibly empty) of tree-sitter node handles otherwise.
//
// When includeDeclaration is false, the declaration site node (startByte ===
// declOffset) is excluded from the result.  Defaults to true (LSP spec: the
// client must opt out explicitly via context.includeDeclaration = false).
export function referencesOf(root, source, cursorOffset, includeDeclaration) {
	let cursorNode = identifierAt(root, cursorOffset);
	if (!cursorNode) return null;

	let targetName = ts.text(cursorNode, source);
	let cursorStart = ts.startByte(cursorNode);

	// Collect all occurrences of targetName with their resolved declaration offset.
	let all = occurrences(root, source, targetName);

	// Determine the anchor: which declaration does the cursor identifier resolve to?
	// anchor = -2 means the cursor node was not found in walk results (should not happen).
	let anchor = -2;
	for (let i = 0; i < length(all); i++) {
		if (ts.startByte(all[i].node) === cursorStart) {
			anchor = all[i].declOffset;
			break;
		}
	}
	if (anchor === -2) return null;

	// Return only occurrences that share the same anchor.
	let result = [];
	for (let i = 0; i < length(all); i++) {
		if (all[i].declOffset !== anchor) continue;
		if (includeDeclaration === false && ts.startByte(all[i].node) === anchor) continue;
		push(result, all[i].node);
	}
	return result;
};
