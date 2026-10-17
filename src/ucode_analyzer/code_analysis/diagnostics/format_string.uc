import * as ts from 'tree_sitter';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { resolveRef } from 'ucode_analyzer.code_analysis.types.type_utils';

let SEVERITY_WARNING = 2;

// Numeric/char conversions: their argument must be a scalar. %s and %J accept
// any value, so they are never type-checked.
const NUMERIC_CONV = 'diuoxXeEfFgGc';

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
//   convChars    conversion chars of the real (argument-consuming, non-positional)
//                specs, in order — so convChars[k] is the conversion for arg k
//   positional   true if any %N$ positional spec is present
//   lengthMods   list of unsupported length-modifier specifier texts
function scanFormat(s) {
	let convChars = [], positional = false, lengthMods = [];
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
			if (!positional) push(convChars, c);
		} else if (index(LENGTH_MODS, c) >= 0) {
			while (i < n && index(LENGTH_MODS, substr(s, i, 1)) >= 0) i++;
			if (i < n) i++;                                  // the intended conversion char
			push(lengthMods, substr(s, start, i - start));
		}
		// else: '%' followed by a non-conversion char — ucode prints it
		// literally, so it is not a spec and consumes no argument. Leave i
		// as-is; the char is scanned as ordinary text next iteration.
	}
	return { convChars, positional, lengthMods };
}

// A structured value (list/dict/record/function/module) has no meaningful numeric
// rendering — ucode coerces it to 0 (or nan). Scalars are deliberately excluded:
// numeric strings parse, floats truncate, null → 0, all plausibly intentional.
// Unknown/any/union/nullable are conservatively treated as OK (not flagged).
function isStructured(t) {
	if (!t) return false;
	t = resolveRef(t);
	let k = t.kind;
	return k === 'record' || k === 'generic' || k === 'function' || k === 'module';
}

function typeName(t) {
	if (t.kind === 'generic') return t.base;   // 'list' / 'dict'
	return t.kind;                              // 'record' / 'function' / 'module'
}

function checkCall(args, source, uri, scopeMap, lineTable, diags) {
	let fmtNode = args[0];
	let info    = scanFormat(formatContent(fmtNode, source));
	let range   = rangeOf(source, lineTable, fmtNode);

	for (let spec in info.lengthMods)
		push(diags, {
			range, severity: SEVERITY_WARNING, source: 'ucode-analyzer',
			code: 'invalid-format-specifier',
			message: sprintf("Format specifier '%s' uses a length modifier, which ucode does not support — it is printed literally", spec),
		});

	// Argument count + type checks: only when the mapping is reliable — no length
	// modifiers (they consume no argument and signal the real problem already) and
	// no positional specs (argument order is index-based). Also skip if any
	// argument is a spread (unknown count).
	if (length(info.lengthMods) > 0 || info.positional) return;
	for (let i = 1; i < length(args); i++)
		if (ts.nodeType(args[i]) === 'spread_element') return;

	let given = length(args) - 1;
	if (length(info.convChars) !== given)
		push(diags, {
			range, severity: SEVERITY_WARNING, source: 'ucode-analyzer',
			code: 'format-argument-count',
			message: sprintf("Format string expects %d argument(s) but %d given", length(info.convChars), given),
		});

	// Type check: a numeric/char conversion whose argument is a structured value
	// (list/dict/record/function/module) is a real bug — ucode renders it as 0/nan.
	for (let k = 0; k < length(info.convChars); k++) {
		let c = info.convChars[k];
		if (index(NUMERIC_CONV, c) < 0) continue;   // %s / %J accept anything
		let argNode = args[k + 1];
		if (!argNode) continue;                     // missing arg already reported
		let scope = scopeAtOffset(scopeMap, ts.startByte(argNode));
		let t = inferNode(argNode, source, uri, scope, 0);
		if (isStructured(t))
			push(diags, {
				range: rangeOf(source, lineTable, argNode),
				severity: SEVERITY_WARNING, source: 'ucode-analyzer',
				code: 'format-argument-type',
				message: sprintf("Conversion '%%%s' expects a number but its argument is a %s", c, typeName(resolveRef(t))),
			});
	}
}

export function formatString(uri, doc) {
	let source = doc.text;
	let diags = [];
	for (let node in ts.descendants(ts.rootNode(doc.tree), ['call_expression'])) {
		let callee   = ts.childByField(node, 'function');
		let argsNode = ts.childByField(node, 'arguments');
		if (!callee || ts.nodeType(callee) !== 'identifier' || !argsNode) continue;
		let name = ts.text(callee, source);
		if (name !== 'sprintf' && name !== 'printf') continue;
		let args = ts.namedChildren(argsNode);
		if (length(args) >= 1 && ts.nodeType(args[0]) === 'string')
			checkCall(args, source, uri, doc.scopeMap, doc.lineTable, diags);
	}
	return diags;
};
