import * as ts from 'tree_sitter';
import { rangeOf } from 'code_analysis.positions';

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
			let ct    = ts.nodeType(child);
			// A field key is either an explicit `key: value` pair or a `{ foo }`
			// shorthand whose identifier is the key. Both collide with each other
			// (`{ foo, foo: 3 }` is a real duplicate).
			let key      = null;
			let rangeNode = child;
			if (ct === 'pair') {
				rangeNode = ts.childByField(child, 'key');
				if (rangeNode) key = keyText(rangeNode, source);
			} else if (ct === 'shorthand_property_identifier') {
				key = ts.text(child, source);
			}
			if (key === null) continue;
			if (exists(seen, key)) {
				push(diags, {
					range:    rangeOf(source, lineTable, rangeNode),
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
	let lineTable = doc.lineTable;
	let diags     = [];
	walk(root, source, lineTable, diags);
	return diags;
};
