import * as fs from 'fs';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';

let KIND_FUNCTION = 12;
let KIND_VARIABLE = 13;

export function workspaceSymbol(query) {
	let q = lc(query ?? '');
	let results = [];

	for (let uri in dag.allUris()) {
		let exports = dag.exportsOf(uri);
		if (!exports) continue;

		// Derive a human-readable container name from the URI (last path component).
		let container = fs.basename(uri);

		for (let i = 0; i < length(exports); i++) {
			let exp = exports[i];
			if (q !== '' && index(lc(exp.name), q) < 0) continue;

			let pos = exp.position;
			let location = pos ? {
				uri,
				range: {
					start: pos,
					end:   { line: pos.line, character: pos.character + length(exp.name) },
				},
			} : { uri };

			push(results, {
				name:          exp.name,
				kind:          exp.kind === 'function' ? KIND_FUNCTION : KIND_VARIABLE,
				containerName: container,
				location,
			});
		}
	}

	return results;
};
