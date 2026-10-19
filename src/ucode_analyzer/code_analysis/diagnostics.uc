import { syntaxErrors }         from 'ucode_analyzer.code_analysis.diagnostics.syntax_error';
import { unknownImports }       from 'ucode_analyzer.code_analysis.diagnostics.unknown_import';
import { unknownImportSymbols } from 'ucode_analyzer.code_analysis.diagnostics.unknown_import_symbol';
import { unusedImports }        from 'ucode_analyzer.code_analysis.diagnostics.unused_import';
import { unusedVars }           from 'ucode_analyzer.code_analysis.diagnostics.unused_var';
import { undefinedVars }        from 'ucode_analyzer.code_analysis.diagnostics.undefined_var';
import { preferStrictEquality } from 'ucode_analyzer.code_analysis.diagnostics.prefer_strict_equality';
import { typeErrors }           from 'ucode_analyzer.code_analysis.diagnostics.type_errors';
import { unreachableCode }      from 'ucode_analyzer.code_analysis.diagnostics.unreachable_code';
import { deprecatedUsage }      from 'ucode_analyzer.code_analysis.diagnostics.deprecated';
import { redeclaredVars }       from 'ucode_analyzer.code_analysis.diagnostics.redeclared_var';
import { duplicateObjectKey }   from 'ucode_analyzer.code_analysis.diagnostics.duplicate_key';
import { assignmentToConst }    from 'ucode_analyzer.code_analysis.diagnostics.const_assignment';
import { missingReturn }        from 'ucode_analyzer.code_analysis.diagnostics.missing_return';
import { formatString }         from 'ucode_analyzer.code_analysis.diagnostics.format_string';
import { jsdocConsistency }     from 'ucode_analyzer.code_analysis.diagnostics.jsdoc_param_mismatch';
import { unknownTypes }         from 'ucode_analyzer.code_analysis.diagnostics.unknown_type';
import { typeNameChecks }       from 'ucode_analyzer.code_analysis.diagnostics.type_name';
import { nanArithmetic }        from 'ucode_analyzer.code_analysis.diagnostics.nan_arithmetic';

// Run one diagnostic pass, appending its results to `out`. Each pass is isolated:
// a die() or runtime error in one pass (a parser edge case, a pathological tree)
// must not drop the other passes' diagnostics for this file, nor abort a
// workspace scan diagnosing up to 500 files. On failure the pass contributes
// nothing — we never invent diagnostics (precision over recall) — and log to
// stderr so the bug is still visible.
export function runPass(name, uri, fn, out) {
	try {
		for (let d in fn()) push(out, d);
	} catch (e) {
		warn(sprintf("ucode-analyzer: diagnostic '%s' failed for %s: %s\n", name, uri, e));
	}
};

export function diagnosticsFor(uri, doc) {
	let diags = [];
	runPass('syntax-error',           uri, () => syntaxErrors(doc),              diags);
	runPass('unknown-import',         uri, () => unknownImports(uri, doc),       diags);
	runPass('unknown-import-symbol',  uri, () => unknownImportSymbols(uri, doc), diags);
	runPass('unused-import',          uri, () => unusedImports(doc),             diags);
	runPass('unused-var',             uri, () => unusedVars(doc),                diags);
	runPass('undefined-var',          uri, () => undefinedVars(doc),             diags);
	runPass('prefer-strict-equality', uri, () => preferStrictEquality(doc),      diags);
	runPass('type-errors',            uri, () => typeErrors(uri, doc),           diags);
	runPass('unreachable-code',       uri, () => unreachableCode(doc),           diags);
	runPass('deprecated',             uri, () => deprecatedUsage(uri, doc),      diags);
	runPass('redeclared-var',         uri, () => redeclaredVars(doc),            diags);
	runPass('duplicate-key',          uri, () => duplicateObjectKey(doc),        diags);
	runPass('const-assignment',       uri, () => assignmentToConst(doc),         diags);
	runPass('missing-return',         uri, () => missingReturn(doc),             diags);
	runPass('format-string',          uri, () => formatString(uri, doc),         diags);
	runPass('jsdoc-param-mismatch',   uri, () => jsdocConsistency(doc),          diags);
	runPass('unknown-type',           uri, () => unknownTypes(doc),              diags);
	runPass('impossible-type-check',  uri, () => typeNameChecks(doc),            diags);
	runPass('nan-arithmetic',         uri, () => nanArithmetic(uri, doc),        diags);
	return diags;
};
