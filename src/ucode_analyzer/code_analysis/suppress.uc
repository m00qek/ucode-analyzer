// Suppression comments, ESLint's: `// ucode-analyzer disable-next-line` hides
// the diagnostics that start on the next line, `// ucode-analyzer disable`
// those on its own line (`/* */` and a template's `{# #}` too). Codes after
// the keyword limit it to them (`disable-next-line may-be-null, unused-var`);
// text after ` -- ` is the reason, and is ignored. One line only: a longer
// reach would hide a whole block after a line that opens it.

import * as ts from 'tree_sitter';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';

// `[{]#`: a literal `{#` in code makes the file read as a template (mode.uc).
const DIRECTIVE = /^(\/\/|\/\*|[{]#-?)[ \t]*ucode-analyzer[ \t]+(disable-next-line|disable)([ \t,][^\n]*)?$/;

// Every directive's line → the codes it hides (code → true), or true for all.
function directives(doc) {
	let out = {};
	for (let c in ts.descendants(ts.rootNode(doc.tree), [ 'comment', 'comment_tag' ])) {
		let text = trim(replace(ts.text(c, doc.text), /(\*\/|-?#\})$/, ''));
		let m = match(text, DIRECTIVE);
		if (!m) continue;
		let at = (m[2] === 'disable')
			? ts.startByte(c)
			: ts.endByte(c);
		let line = offsetToPosition(doc.text, doc.lineTable, at).line + (m[2] === 'disable' ? 0 : 1);
		let codes = filter(split(split(m[3] ?? '', ' -- ')[0], /[ \t,]+/), length);
		if (!length(codes) || out[line] === true) { out[line] = true; continue; }
		out[line] ??= {};
		for (let k in codes) out[line][k] = true;
	}
	return out;
}

// diags without those a suppression comment of doc hides.
export function unsuppressed(doc, diags) {
	if (index(doc.text, 'ucode-analyzer') < 0) return diags;
	let hidden = directives(doc);
	return filter(diags, (d) => {
		let h = hidden[d.range.start.line];
		return !h || (h !== true && !h[d.code]);
	});
};
