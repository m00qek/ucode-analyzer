// Per-file source mode: ucode can be a plain script (code) or a template (text
// with embedded {% %} / {{ }} / {# #} tags). Both use the .uc extension, so the
// mode is not derivable from the filename — it must be read from the content.
// Everything that parses a file routes through here so the whole server agrees
// on a file's mode (the DAG and the open-document store must never disagree).

import * as ts from 'tree_sitter';
import { stringLiteralText } from 'code_analysis.ast_text';

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
// root is 'markup' for a template or 'program' for a script. Both grammars share
// one rule set: a template is ucode's statement stream, in which the text between
// `%}` and `{%` is a `text_statement` wherever a statement may appear. So a
// template's code carries the node types — and the nesting — of a script:
// `{% if (c) { %}…{% } %}` is an ordinary if_statement whose statement_block
// holds the text, and downstream analysis applies unchanged.
export function parse(text) {
	return ts.parse(isTemplate(text) ? _templateParser : _scriptParser, text);
};

// The `{%` / `%}` delimiters (with their trim `-` and lstrip `+` variants) that a
// template's root holds between its statements.
const TAG_DELIMITERS = {
	statement_tag_open: true, statement_tag_trim_open: true, statement_tag_lstrip_open: true,
	statement_tag_close: true, statement_tag_trim_close: true,
};

// Yield the logical top-level statements of a parsed file, so callers need not
// know the mode. For a script (program root) these are the root's named children.
// A template's root (markup) holds its statements directly too, interleaved with
// the tag delimiters (dropped here) and the text around the tags — raw_text,
// expression/comment tags, text_statement — which pass through; the caller's
// node-type check ignores what it doesn't handle, exactly as for a script tree.
export function topLevelStatements(root) {
	let out = [];
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let child = ts.namedChild(root, i);
		if (!TAG_DELIMITERS[ts.nodeType(child)]) push(out, child);
	}
	return out;
};

// ── Import-statement structure ──────────────────────────────────────────────
// The import-clause grammar shape lives here so a grammar change is fixed once
// rather than in every feature that reads imports.

// The module specifier string of an import_statement (the '…' part), or null.
export function importStmtSpecifier(stmt, text) {
	for (let i = 0; i < ts.childCount(stmt); i++) {
		let child = ts.child(stmt, i);
		if (ts.nodeType(child) !== 'string') continue;
		let spec = stringLiteralText(child, text);
		return length(spec) ? spec : null;
	}
	return null;
};

// Decompose an import_statement's binding structure:
//   { namespaceAlias: node|null,                // the `x` of `import * as x`
//     specifiers: [{ remoteNode, localNode }] }  // one per `{ a }` / `{ a as b }`
// localNode === remoteNode for a plain `{ a }`; they differ for `{ a as b }`
// (the local binding is the specifier's last named child).
export function importBindings(stmt) {
	let namespaceAlias = null;
	let specifiers = [];
	for (let i = 0; i < ts.namedChildCount(stmt); i++) {
		let clause = ts.namedChild(stmt, i);
		if (ts.nodeType(clause) !== 'import_clause') continue;
		for (let j = 0; j < ts.namedChildCount(clause); j++) {
			let part = ts.namedChild(clause, j);
			let pnt = ts.nodeType(part);
			if (pnt === 'namespace_import') {
				namespaceAlias = ts.namedChild(part, 0);
			} else if (pnt === 'named_imports') {
				for (let k = 0; k < ts.namedChildCount(part); k++) {
					let spec = ts.namedChild(part, k);
					if (ts.nodeType(spec) !== 'import_specifier') continue;
					let count = ts.namedChildCount(spec);
					if (count === 0) continue;
					push(specifiers, {
						remoteNode: ts.namedChild(spec, 0),
						localNode:  ts.namedChild(spec, count - 1),
					});
				}
			}
		}
	}
	return { namespaceAlias, specifiers };
};

// The local binding identifier nodes an import introduces into scope: the
// namespace alias plus each specifier's local name.
export function importBindingNodes(stmt) {
	let b = importBindings(stmt);
	let out = b.namespaceAlias ? [b.namespaceAlias] : [];
	for (let s in b.specifiers)
		if (s.localNode) push(out, s.localNode);
	return out;
};
