import * as mode from 'ucode_analyzer.code_analysis.mode';

// For each diagnostic with a code, in a script (a template line may be text,
// where `//` would be output): a `// ucode-analyzer disable-next-line <code>`
// above its line, indented as it (see suppress.uc).
export function actionsFor(uri, doc, diagnostics) {
	if (mode.isTemplate(doc.text)) return [];
	let actions = [], seen = {};
	for (let d in diagnostics) {
		let line = d.range?.start?.line;
		if (!d.code || line === null || seen[line + ' ' + d.code]) continue;
		seen[line + ' ' + d.code] = true;
		let start = doc.lineTable[line];
		let indent = match(substr(doc.text, start, 200), /^[ \t]*/)?.[0] ?? '';
		let at = { line, character: 0 };
		push(actions, {
			title: sprintf("Disable %s for this line", d.code),
			kind: 'quickfix',
			diagnostics: [ d ],
			edit: { changes: { [uri]: [ { range: { start: at, end: at },
				newText: sprintf('%s// ucode-analyzer disable-next-line %s\n', indent, d.code) } ] } },
		});
	}
	return actions;
};
