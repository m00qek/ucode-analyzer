// Per-file source mode: ucode can be a plain script (code) or a template (text
// with embedded {% %} / {{ }} / {# #} tags). Both use the .uc extension, so the
// mode is not derivable from the filename — it must be read from the content.
// Everything that parses a file routes through here so the whole server agrees
// on a file's mode (the DAG and the open-document store must never disagree).

import * as ts from 'tree_sitter';
import { stringLiteralText } from 'ucode_analyzer.code_analysis.ast_text';

let _scriptParser   = ts.newParser(ts.ucode());
let _templateParser = ts.newParser(ts.markup());

// A string literal delimited by q, with backslash escapes; unterminated, it
// runs to the end.
function quoted(q) {
	return q + '([^' + q + '\\\\]|\\\\.)*(' + q + '|\\\\?$)';
}

// One token per match: a comment or string literal is consumed whole, so an
// opener inside it is never seen, and an unterminated one runs to the end.
// Built from strings: the quotes of a regex literal would derail the scan of
// this very file.
const TOKENS = regexp(join('|', [
	'//[^\n]*',
	'/\\*([^*]|\\*+[^*/])*(\\*+/|\\**$)',
	quoted('"'), quoted("'"), quoted('`'),
	'\\{[%{#]',
]), 'g');

// Whether an opener is in code position by a scan of the text: strings and
// comments skipped, an unterminated one running to the end as in ucode. It
// cannot tell a regex literal from a division, so it reads an opener inside a
// regex as code; classify asks it only where the parse cannot tell.
function scannedTag(text) {
	for (let m in match(text, TOKENS))
		if (substr(m[0], 0, 1) === '{') return true;
	return false;
}

// Where a script holds a literal: an opener inside one is text, not a tag. A
// template string's ${ } is code again.
const LITERALS = { string: true, regex: true, comment: true, doc_comment: true };

function inLiteral(root, offset) {
	for (let n = ts.descendantAt(root, offset); n; n = ts.parent(n)) {
		let t = ts.nodeType(n);
		if (LITERALS[t]) return true;
		if (t === 'template_substitution') return false;
		if (t === 'template_string') return true;
	}
	return false;
}

// Parse the source as a script and report whether a template tag opener
// ({% / {{ / {#) is in code position: { template, tree }, tree the script's
// parse. In a valid script such openers can only be inside strings, regexes
// or comments — as bare syntax they are a hard parse error — so one in code
// position means the file must be a template. A clean parse tells a regex
// from a division as ucode does; a parse with errors (a template, or a script
// left unterminated while typed) recovers unlike ucode, so the scan of the
// text decides.
//
// Residual gap: a template whose only tag sits inside a quoted run of raw text
// (e.g. `<a href="{{ url }}">` with no other tag) reads as a script, because
// the quotes parse as a string. Vanishingly rare and unobserved in the corpus.
function classify(text) {
	let tree = ts.parse(_scriptParser, text);
	let root = ts.rootNode(tree);
	for (let opener in [ '{%', '{{', '{#' ])
		for (let from = 0, at; (at = index(substr(text, from), opener)) >= 0; from += at + 2)
			if (!inLiteral(root, from + at))
				return { template: ts.hasError(root) ? scannedTag(text) : true, tree };
	return { template: false, tree };
}

// The mode a shebang records, or null: `utpl` or a `-T` flag selects template
// mode, `-R` forces a raw script, and a plain `#!/usr/bin/ucode` carries none.
function shebangMode(text) {
	if (substr(text, 0, 2) !== '#!') return null;
	let nl = index(text, "\n");
	let shebang = (nl >= 0) ? substr(text, 0, nl) : text;
	if (index(shebang, 'utpl') >= 0 || index(shebang, '-T') >= 0) return true;
	if (index(shebang, '-R') >= 0) return false;
	return null;
}

// Most scripts contain no opener at all.
function hasOpener(text) {
	return index(text, '{%') >= 0 || index(text, '{{') >= 0 || index(text, '{#') >= 0;
}

// Does the source use template mode?
//
// ucode itself picks the mode by how it is invoked (`ucode` / `-R` ⇒ raw script,
// the default; `ucode -T` or the `utpl` symlink ⇒ template). A shebang is the
// in-file record of that choice, so it wins when present. Otherwise we detect by
// content: a template tag opener in code position (see classify).
//
// Validated against the ucode interpreter over the firewall4 corpus (33/33 files
// classified identically).
export function isTemplate(text) {
	let m = shebangMode(text);
	if (m !== null) return m;
	return hasOpener(text) && classify(text).template;
};

// ── Blocks left open at the end of the file ─────────────────────────────────
// tree-sitter recovers a block left open at EOF by inserting a MISSING `}`, but
// each insertion has a fixed cost while an ERROR wrapping the file costs more as
// the file grows. So in a small file with two or more open blocks the whole file
// becomes one ERROR: no function, no scopes, no outline. parse() then appends
// the missing closers and parses again; syntaxErrors() reports the appended
// closers (appendedClosers) as missing, as it does MISSING nodes.

const CLOSER_OF = { '{': '}', '(': ')', '[': ']' };

// An alt-syntax keyword whose `:` opens a body closed by its `end…` keyword.
const ALT_END = { 'if': 'endif', 'for': 'endfor', 'while': 'endwhile', 'function': 'endfunction' };

// Push the closers an ERROR node's tokens leave open onto `stack`. Named
// children are complete constructs, already balanced; only the ERROR's own
// tokens (and those of nested ERRORs) open or close. Strings, comments, regexes
// and template literals are named nodes, so their brackets never count.
function openClosers(node, stack, alt) {
	for (let i = 0; i < ts.childCount(node); i++) {
		let c = ts.child(node, i);
		let t = ts.nodeType(c);
		if (t === 'ERROR')
			openClosers(c, stack, alt);
		else if (ts.isNamed(c))
			continue;
		else if (CLOSER_OF[t]) {
			push(stack, CLOSER_OF[t]);
			alt.closer = null;
		}
		else if (length(stack) && t === stack[-1])
			pop(stack);
		else if (ALT_END[t]) {
			alt.closer = ALT_END[t];
			alt.depth = length(stack);
		}
		else if (t === ':' && alt.closer && alt.depth === length(stack)) {
			push(stack, alt.closer);
			alt.closer = null;
		}
		else if (t === ';')
			alt.closer = null;
	}
}

// The closers missing at the end of the file, innermost first, when an ERROR
// (the root itself, or the root's last child) runs to the end; else null.
function missingClosers(tree) {
	let root = ts.rootNode(tree);
	if (!ts.hasError(root)) return null;
	let err = root;
	if (ts.nodeType(root) !== 'ERROR') {
		let n = ts.childCount(root);
		err = n ? ts.child(root, n - 1) : null;
		if (!err || ts.nodeType(err) !== 'ERROR') return null;
	}
	let stack = [];
	openClosers(err, stack, { closer: null, depth: 0 });
	return length(stack) ? reverse(stack) : null;
}

// Parse source with the grammar matching its detected mode. Returns a tree whose
// root is 'markup' for a template or 'program' for a script. Both grammars share
// one rule set: a template is ucode's statement stream, in which the text between
// `%}` and `{%` is a `text_statement` wherever a statement may appear. So a
// template's code carries the node types — and the nesting — of a script:
// `{% if (c) { %}…{% } %}` is an ordinary if_statement whose statement_block
// holds the text, and downstream analysis applies unchanged.
//
// When blocks left open at EOF turn the file into one ERROR (see above), the
// tree returned is that of the text with the missing closers appended, so its
// last nodes end past length(text). The `\n` ends a trailing line comment; the
// spaces keep `} }` from lexing as a template's `}}`.
export function parse(text) {
	let m = shebangMode(text), tree = null;
	if (m === null && hasOpener(text)) {
		let c = classify(text);
		m = c.template;
		if (!m) tree = c.tree;
	}
	let parser = m ? _templateParser : _scriptParser;
	tree ??= ts.parse(parser, text);
	let closers = missingClosers(tree);
	if (!closers) return tree;
	let closed = ts.parse(parser, text + "\n" + join(' ', closers));
	return ts.nodeType(ts.rootNode(closed)) === 'ERROR' ? tree : closed;
};

function collectAppended(node, textEnd, out) {
	for (let i = 0; i < ts.childCount(node); i++) {
		let c = ts.child(node, i);
		if (ts.endByte(c) <= textEnd) continue;
		if (ts.childCount(c) > 0)
			collectAppended(c, textEnd, out);
		else if (ts.startByte(c) >= textEnd && !ts.isMissing(c))
			push(out, c);
	}
}

// The closer tokens parse() appended past the end of `text`, innermost first;
// none for a tree parsed from `text` alone.
export function appendedClosers(tree, text) {
	let out = [];
	collectAppended(ts.rootNode(tree), length(text), out);
	return out;
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
	let src = ts.childByField(stmt, 'source');
	if (!src || ts.nodeType(src) !== 'string') return null;
	let spec = stringLiteralText(src, text);
	return length(spec) ? spec : null;
};

// Decompose an import_statement's binding structure:
//   { namespaceAlias: node|null,                // the `x` of `import * as x`
//     specifiers: [{ remoteNode, localNode }] }  // `import x`, `{ a }`, `{ a as b }`
// localNode === remoteNode for a plain `{ a }`. A default import (`import x`)
// has remoteNode null; importRemoteName reads it as `default`.
export function importBindings(stmt) {
	let namespaceAlias = null;
	let specifiers = [];
	let clause = ts.childByField(stmt, 'clause');
	if (!clause) return { namespaceAlias, specifiers };

	let def = ts.childByField(clause, 'default');
	if (def) push(specifiers, { remoteNode: null, localNode: def });

	let ns = ts.childByField(clause, 'namespace');
	if (ns) {
		for (let i = 0; i < ts.namedChildCount(ns); i++) {
			let id = ts.namedChild(ns, i);
			if (ts.nodeType(id) === 'identifier') { namespaceAlias = id; break; }
		}
	}

	let named = ts.childByField(clause, 'named');
	for (let i = 0; named && i < ts.namedChildCount(named); i++) {
		let spec = ts.namedChild(named, i);
		if (ts.nodeType(spec) !== 'import_specifier') continue;
		let remote = ts.childByField(spec, 'name');
		if (!remote) continue;
		push(specifiers, { remoteNode: remote, localNode: ts.childByField(spec, 'alias') ?? remote });
	}
	return { namespaceAlias, specifiers };
};

// The exported name a specifier imports: `default` for a default import or
// `{ default as x }`, a quoted name without its quotes.
export function importRemoteName(spec, text) {
	let n = spec.remoteNode;
	if (!n) return 'default';
	return ts.nodeType(n) === 'string' ? stringLiteralText(n, text) : ts.text(n, text);
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
