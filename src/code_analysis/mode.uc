// Per-file source mode: ucode can be a plain script (code) or a template (text
// with embedded {% %} / {{ }} / {# #} tags). Both use the .uc extension, so the
// mode is not derivable from the filename — it must be read from the content.
// Everything that parses a file routes through here so the whole server agrees
// on a file's mode (the DAG and the open-document store must never disagree).

import * as ts from 'tree_sitter';

let _scriptParser   = ts.newParser(ts.ucode());
let _templateParser = ts.newParser(ts.markup());

// Does the source use template mode? Heuristic: any line whose first
// non-whitespace characters open a template tag ({% / {{ / {#). This mirrors
// the tree-sitter-ucode grammar's own content-regex (^\s*\{[%{#]) used for
// editor detection, and it sidesteps false positives from a script's own
// "{{ }}" string literals (those are not at a line start). Known gap, to close
// against the ucode oracle in Strand 3: a template whose only tag sits mid-line
// (e.g. inside an HTML attribute) is misread as a script.
export function isTemplate(text) {
	for (let line in split(text, "\n")) {
		let head = substr(trim(line), 0, 2);
		if (head === '{%' || head === '{{' || head === '{#')
			return true;
	}
	return false;
};

// Parse source with the grammar matching its detected mode. Returns a tree whose
// root is 'markup' for a template or 'program' for a script; the code *inside*
// template tags carries the same node types as a script, so downstream analysis
// applies unchanged once it descends through the tag wrappers.
export function parse(text) {
	return ts.parse(isTemplate(text) ? _templateParser : _scriptParser, text);
};
