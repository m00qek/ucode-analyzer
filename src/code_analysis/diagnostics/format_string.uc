import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'code_analysis.positions';

let SEVERITY_WARNING = 2;

// ucode's sprintf/printf accept these conversion characters. Determined
// empirically against the interpreter: ucode does NOT support C length modifiers
// (%ld, %lld, %zu, …) — it prints any specifier it can't parse *literally* and
// leaves the corresponding argument unconsumed, rather than erroring. A '%'
// followed by flags/width/precision then a valid conversion consumes one
// argument; anything else (a stray '%', "100%!", a length modifier) is emitted
// verbatim. Positional args (%2$d) and %% are supported.
const VALID_CONV  = 'diuoxXeEfFgGcsJ';
const LENGTH_MODS = 'lhLqjzt';
const FLAGS       = '-+ #0';
const SENTINEL    = chr(1);  // stands in for an escape sequence while scanning

function isDigit(c) { return c !== '' && index('0123456789', c) >= 0; }

// Reconstruct the format string's logical characters, replacing each escape
// sequence with an opaque non-'%' placeholder. Escapes never contain a format
// spec, and the placeholder stops an escape adjacent to a '%' (e.g. "50%\n")
// from being misread as part of a conversion.
function formatContent(node, source) {
	let out = '';
	for (let k = 0; k < ts.childCount(node); k++) {
		let ch = ts.child(node, k);
		let t  = ts.nodeType(ch);
		if (t === 'string_fragment')       out += ts.text(ch, source);
		else if (t === 'escape_sequence')  out += SENTINEL;
	}
	return out;
}

// Scan a format string, returning:
//   convs        number of real (argument-consuming) conversions
//   positional   true if any %N$ positional spec is present
//   lengthMods   list of unsupported length-modifier specifier texts
function scanFormat(s) {
	let convs = 0, positional = false, lengthMods = [];
	let n = length(s);
	let i = 0;
	while (i < n) {
		if (substr(s, i, 1) !== '%') { i++; continue; }
		let start = i;
		i++;
		if (i >= n) break;                                   // trailing '%' → literal
		if (substr(s, i, 1) === '%') { i++; continue; }      // %% → literal percent

		// positional: %<digits>$
		let j = i;
		while (j < n && isDigit(substr(s, j, 1))) j++;
		if (j > i && j < n && substr(s, j, 1) === '$') { positional = true; i = j + 1; }

		while (i < n && index(FLAGS, substr(s, i, 1)) >= 0) i++;          // flags
		while (i < n && isDigit(substr(s, i, 1))) i++;                     // width
		if (i < n && substr(s, i, 1) === '.') {                           // precision
			i++;
			while (i < n && isDigit(substr(s, i, 1))) i++;
		}
		if (i >= n) break;

		let c = substr(s, i, 1);
		if (index(VALID_CONV, c) >= 0) {
			i++;
			if (!positional) convs++;
		} else if (index(LENGTH_MODS, c) >= 0) {
			while (i < n && index(LENGTH_MODS, substr(s, i, 1)) >= 0) i++;
			if (i < n) i++;                                  // the intended conversion char
			push(lengthMods, substr(s, start, i - start));
		}
		// else: '%' followed by a non-conversion char — ucode prints it
		// literally, so it is not a spec and consumes no argument. Leave i
		// as-is; the char is scanned as ordinary text next iteration.
	}
	return { convs, positional, lengthMods };
}

function checkCall(args, source, lineTable, diags) {
	let fmtNode = args[0];
	let info    = scanFormat(formatContent(fmtNode, source));
	let range   = rangeOf(source, lineTable, fmtNode);

	for (let spec in info.lengthMods)
		push(diags, {
			range, severity: SEVERITY_WARNING, source: 'ucode-ls',
			code: 'invalid-format-specifier',
			message: sprintf("Format specifier '%s' uses a length modifier, which ucode does not support — it is printed literally", spec),
		});

	// Argument count: only when reliable — no length modifiers (they consume no
	// argument and signal the real problem already) and no positional specs
	// (argument order is index-based). Also skip if any argument is a spread.
	if (length(info.lengthMods) > 0 || info.positional) return;
	for (let i = 1; i < length(args); i++)
		if (ts.nodeType(args[i]) === 'spread_element') return;

	let given = length(args) - 1;
	if (info.convs !== given)
		push(diags, {
			range, severity: SEVERITY_WARNING, source: 'ucode-ls',
			code: 'format-argument-count',
			message: sprintf("Format string expects %d argument(s) but %d given", info.convs, given),
		});
}

let _walk;
_walk = function(node, source, lineTable, diags) {
	if (ts.nodeType(node) === 'call_expression') {
		let callee   = ts.childByField(node, 'function');
		let argsNode = ts.childByField(node, 'arguments');
		if (callee && ts.nodeType(callee) === 'identifier' && argsNode) {
			let name = ts.text(callee, source);
			if (name === 'sprintf' || name === 'printf') {
				let args = [];
				for (let i = 0; i < ts.namedChildCount(argsNode); i++)
					push(args, ts.namedChild(argsNode, i));
				if (length(args) >= 1 && ts.nodeType(args[0]) === 'string')
					checkCall(args, source, lineTable, diags);
			}
		}
	}
	for (let i = 0; i < ts.namedChildCount(node); i++)
		_walk(ts.namedChild(node, i), source, lineTable, diags);
};

export function formatString(doc) {
	let source    = doc.text;
	let lineTable = buildLineTable(source);
	let diags     = [];
	_walk(ts.rootNode(doc.tree), source, lineTable, diags);
	return diags;
};
