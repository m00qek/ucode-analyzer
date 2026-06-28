import { unknownImports } from 'language_server.diagnostics.unknown_imports';

export function diagnosticsFor(uri, doc) {
	return unknownImports(uri, doc);
};
