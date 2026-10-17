import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

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

function checkObject(node, source, lineTable, diags) {
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
			push(diags, diagnostic(rangeOf(source, lineTable, rangeNode), Severity.WARNING, 'duplicate-key',
				sprintf("Duplicate key '%s' in object literal", key)));
		} else {
			seen[key] = true;
		}
	}
}

export function duplicateObjectKey(doc) {
	let diags = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), ['object']))
		checkObject(node, doc.text, doc.lineTable, diags);
	return diags;
};
