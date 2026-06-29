import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';

let SEVERITY_WARNING = 2;

// Extract a string key from a pair's key node, or null for computed keys.
function keyText(keyNode, source) {
	let nt = ts.nodeType(keyNode);
	if (nt === 'property_identifier') return ts.text(keyNode, source);
	if (nt === 'string') {
		// Strip surrounding quotes.
		let raw = ts.text(keyNode, source);
		return substr(raw, 1, length(raw) - 2);
	}
	return null;  // computed key [expr] — skip
}

function walk(node, source, lineTable, diags) {
	if (ts.nodeType(node) === 'object') {
		let seen = {};
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let child = ts.namedChild(node, i);
			if (ts.nodeType(child) !== 'pair') continue;
			let keyNode = ts.childByField(child, 'key');
			if (!keyNode) continue;
			let key = keyText(keyNode, source);
			if (key === null) continue;
			if (exists(seen, key)) {
				push(diags, {
					range:    rangeOf(source, lineTable, keyNode),
					severity: SEVERITY_WARNING,
					source:   'ucode-ls',
					code:     'duplicate-key',
					message:  sprintf("Duplicate key '%s' in object literal", key),
				});
			} else {
				seen[key] = true;
			}
		}
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), source, lineTable, diags);
}

export function duplicateObjectKey(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = buildLineTable(source);
	let diags     = [];
	walk(root, source, lineTable, diags);
	return diags;
};
