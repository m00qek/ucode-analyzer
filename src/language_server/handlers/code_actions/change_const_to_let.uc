export function actionsFor(uri, doc, diagnostics) {
	let actions  = [];
	let seen     = {};  // deduplicate by constKeywordRange start

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'const-assignment') continue;

		let kwRange = diag.data?.constKeywordRange;
		if (!kwRange) continue;

		// Deduplicate: multiple assignments to the same const produce one fix.
		let key = sprintf('%d:%d', kwRange.start.line, kwRange.start.character);
		if (exists(seen, key)) continue;
		seen[key] = true;

		push(actions, {
			title:       "Change 'const' to 'let'",
			kind:        'quickfix',
			diagnostics: [diag],
			isPreferred: false,
			edit: {
				changes: { [uri]: [{ range: kwRange, newText: 'let' }] },
			},
		});
	}

	return actions;
};
