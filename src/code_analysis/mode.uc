// Per-file source mode: ucode can be a plain script (code) or a template (text
// with embedded {% %} / {{ }} / {# #} tags). Both use the .uc extension, so the
// mode is not derivable from the filename — it must be read from the content.
// Everything that parses a file routes through here so the whole server agrees
// on a file's mode (the DAG and the open-document store must never disagree).

import * as ts from 'tree_sitter';

let _scriptParser   = ts.newParser(ts.ucode());
let _templateParser = ts.newParser(ts.markup());

// Scan the source as if it were a script, skipping string literals ('...',
// "...", `...`) and comments (// and block comments), and report whether a
// template tag opener ({% / {{ / {#) appears in *code* position. In a valid raw
// script such openers can only occur inside strings or comments — as bare syntax
// they are a hard parse error — so an opener in code position means the file must
// be a template. This catches a tag anywhere on a line, not only at its start,
// while ignoring a script's own "{{ }}" string content.
//
// Residual gap: a template whose only tag sits inside a quoted run of raw text
// (e.g. `<a href="{{ url }}">` with no other tag) is skipped, because the scan
// treats the quotes as a string. Vanishingly rare and unobserved in the corpus.
function hasCodePositionTag(text) {
	let n = length(text);
	let i = 0;
	while (i < n) {
		let c = substr(text, i, 1);
		if (c === '/' && substr(text, i + 1, 1) === '/') {           // line comment
			i += 2;
			while (i < n && substr(text, i, 1) !== "\n") i++;
			continue;
		}
		if (c === '/' && substr(text, i + 1, 1) === '*') {           // block comment
			i += 2;
			while (i < n && !(substr(text, i, 1) === '*' && substr(text, i + 1, 1) === '/')) i++;
			i += 2;
			continue;
		}
		if (c === '"' || c === "'" || c === '`') {                   // string literal
			i++;
			while (i < n) {
				let d = substr(text, i, 1);
				if (d === '\\') { i += 2; continue; }                // skip escape
				if (d === c) { i++; break; }
				i++;
			}
			continue;
		}
		if (c === '{') {
			let d = substr(text, i + 1, 1);
			if (d === '%' || d === '{' || d === '#') return true;    // {% / {{ / {#
		}
		i++;
	}
	return false;
}

// Does the source use template mode?
//
// ucode itself picks the mode by how it is invoked (`ucode` / `-R` ⇒ raw script,
// the default; `ucode -T` or the `utpl` symlink ⇒ template). A shebang is the
// in-file record of that choice, so it wins when present. Otherwise we detect by
// content: a template tag opener in code position (see hasCodePositionTag).
//
// Validated against the ucode interpreter over the firewall4 corpus (33/33 files
// classified identically).
export function isTemplate(text) {
	if (substr(text, 0, 2) === '#!') {
		let nl = index(text, "\n");
		let shebang = (nl >= 0) ? substr(text, 0, nl) : text;
		// `utpl` or a `-T` flag selects template mode; `-R` forces raw script.
		if (index(shebang, 'utpl') >= 0 || index(shebang, '-T') >= 0) return true;
		if (index(shebang, '-R') >= 0) return false;
		// A plain `#!/usr/bin/ucode` carries no mode flag → fall through to content.
	}
	return hasCodePositionTag(text);
};

// Parse source with the grammar matching its detected mode. Returns a tree whose
// root is 'markup' for a template or 'program' for a script; the code *inside*
// template tags carries the same node types as a script, so downstream analysis
// applies unchanged once it descends through the tag wrappers.
export function parse(text) {
	return ts.parse(isTemplate(text) ? _templateParser : _scriptParser, text);
};

// Yield the logical top-level statements of a parsed file, transparently
// unwrapping template statement tags so callers need not know the mode. For a
// script (program root) these are simply the root's named children. For a
// template (markup root) a `{% stmt; ... %}` block wraps its statements in a
// `statement_tag` node — we descend one level into each and surface the real
// statements (dropping the `statement_tag_open`/`_close` delimiters). Spanning
// forms (`for_in_alt_statement`, …) and non-statement children (`raw_text`,
// `expression_tag`) pass through as-is; the caller's node-type check ignores what
// it doesn't handle, exactly as it does for a script tree.
export function topLevelStatements(root) {
	let out = [];
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let child = ts.namedChild(root, i);
		if (ts.nodeType(child) !== 'statement_tag') {
			push(out, child);
			continue;
		}
		for (let j = 0; j < ts.namedChildCount(child); j++) {
			let inner = ts.namedChild(child, j);
			let it = ts.nodeType(inner);
			if (it === 'statement_tag_open' || it === 'statement_tag_close') continue;
			push(out, inner);
		}
	}
	return out;
};
