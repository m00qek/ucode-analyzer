// LSP enumerations, by the specification's names, and the diagnostic shape.
// Each enumeration is its own object: a function is 3 as a completion item
// but 12 as a symbol.

export const Severity           = { ERROR: 1, WARNING: 2, INFO: 3, HINT: 4 };
export const DiagnosticTag      = { UNNECESSARY: 1, DEPRECATED: 2 };
export const SymbolKind         = { MODULE: 2, FUNCTION: 12, VARIABLE: 13, CONSTANT: 14 };
export const CompletionItemKind = { FUNCTION: 3, VARIABLE: 6, MODULE: 9, KEYWORD: 14 };
export const HighlightKind      = { TEXT: 1, READ: 2, WRITE: 3 };
export const InlayHintKind      = { TYPE: 1, PARAMETER: 2 };
export const FileChangeType     = { CREATED: 1, CHANGED: 2, DELETED: 3 };

// A diagnostic from this analyzer.
export function diagnostic(range, severity, code, message) {
	return { range, severity, source: 'ucode-analyzer', code, message };
};
