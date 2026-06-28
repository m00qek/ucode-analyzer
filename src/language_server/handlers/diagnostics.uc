import { syntaxErrors } from 'language_server.diagnostics.syntax_errors';
import { unknownImports } from 'language_server.diagnostics.unknown_imports';

export function diagnosticsFor(uri, doc) {
	let diags = [];
	for (let d in syntaxErrors(doc))       push(diags, d);
	for (let d in unknownImports(uri, doc)) push(diags, d);
	return diags;
};
