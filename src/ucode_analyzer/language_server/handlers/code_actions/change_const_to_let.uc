export function actionsFor(uri, doc, diagnostics) {
	let actions  = [];
	let seen     = {};  // deduplicate by constKeywordRange start

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'const-assignment') continue;

		let kwRange = diag.data?.constKeywordRange;
		if (!kwRange) continue;

		// Several assignments to the same const: one fix, which resolves them all.
		let key = sprintf('%d:%d', kwRange.start.line, kwRange.start.character);
		if (exists(seen, key)) {
			push(seen[key].diagnostics, diag);
			continue;
		}

		seen[key] = {
			title:       "Change 'const' to 'let'",
			kind:        'quickfix',
			diagnostics: [diag],
			isPreferred: false,
			edit: {
				changes: { [uri]: [{ range: kwRange, newText: 'let' }] },
			},
		};
		push(actions, seen[key]);
	}

	return actions;
};
