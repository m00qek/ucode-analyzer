// A JSDoc type name that no @typedef defines. The annotation then types
// nothing (the value is unknown) without saying so; most often it is a typo,
// or a JavaScript name ucdocs spells otherwise (`RegExp` for regexp).

import * as ts from 'tree_sitter';
import { typeNames } from 'ucode_analyzer.code_analysis.types.doc_parser';
import * as type_registry from 'ucode_analyzer.code_analysis.types.registry';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

// The names ucdocs reads as types of their own (ucdocs grammar).
const BUILTIN = [ 'int', 'integer', 'float', 'double', 'number', 'string', 'boolean', 'null', 'void',
	'function', 'object', 'array', 'regexp', 'resource', 'any', 'list', 'dict' ];

// A known type name that name differs from only in case, or null.
function suggestion(name) {
	let lower = lc(name);
	for (let k in [ ...BUILTIN, ...sort(type_registry.allNames()) ])
		if (lc(k) === lower) return k;
	return null;
}

export function unknownTypes(doc) {
	let out = [];
	for (let c in ts.descendants(ts.rootNode(doc.tree), [ 'doc_comment' ])) {
		let base = ts.startByte(c);
		for (let t in typeNames(ts.text(c, doc.text))) {
			if (type_registry.lookup(t.name)) continue;
			let s = suggestion(t.name);
			push(out, diagnostic({
				start: offsetToPosition(doc.text, doc.lineTable, base + t.start),
				end:   offsetToPosition(doc.text, doc.lineTable, base + t.end),
			}, Severity.WARNING, 'unknown-type', s
				? sprintf("Unknown type '%s': did you mean '%s'?", t.name, s)
				: sprintf("Unknown type '%s': no @typedef defines it", t.name)));
		}
	}
	return out;
};
