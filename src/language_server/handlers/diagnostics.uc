import { syntaxErrors }          from 'language_server.diagnostics.syntax_errors';
import { unknownImports }         from 'language_server.diagnostics.unknown_imports';
import { unknownImportSymbols }   from 'language_server.diagnostics.unknown_import_symbols';
import { unusedVars }             from 'language_server.diagnostics.unused_vars';
import { undefinedVars }          from 'language_server.diagnostics.undefined_vars';

export function diagnosticsFor(uri, doc) {
	let diags = [];
	for (let d in syntaxErrors(doc))             push(diags, d);
	for (let d in unknownImports(uri, doc))       push(diags, d);
	for (let d in unknownImportSymbols(uri, doc)) push(diags, d);
	for (let d in unusedVars(doc))                push(diags, d);
	for (let d in undefinedVars(doc))             push(diags, d);
	return diags;
};
