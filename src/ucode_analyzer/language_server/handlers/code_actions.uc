import { actionsFor as preferStrictEquality } from 'ucode_analyzer.language_server.handlers.code_actions.prefer_strict_equality';
import { actionsFor as removeUnusedImport }   from 'ucode_analyzer.language_server.handlers.code_actions.remove_unused_import';
import { actionsFor as removeDuplicateKey }   from 'ucode_analyzer.language_server.handlers.code_actions.remove_duplicate_key';
import { actionsFor as changeConstToLet }     from 'ucode_analyzer.language_server.handlers.code_actions.change_const_to_let';
import { actionsFor as useOptionalChain }     from 'ucode_analyzer.language_server.handlers.code_actions.use_optional_chain';
import { actionsFor as addMissingImport }     from 'ucode_analyzer.language_server.handlers.code_actions.add_missing_import';
import { actionsFor as generateJsdoc }        from 'ucode_analyzer.language_server.handlers.code_actions.generate_jsdoc';
import { actionsFor as suppressDiagnostic }   from 'ucode_analyzer.language_server.handlers.code_actions.suppress_diagnostic';

// `range` (optional): the request's selection, for refactorings at the cursor.
export function codeAction(uri, doc, diagnostics, range) {
	let actions = [];
	for (let a in preferStrictEquality(uri, doc, diagnostics)) push(actions, a);
	for (let a in removeUnusedImport(uri, doc, diagnostics))   push(actions, a);
	for (let a in removeDuplicateKey(uri, doc, diagnostics))   push(actions, a);
	for (let a in changeConstToLet(uri, doc, diagnostics))     push(actions, a);
	for (let a in useOptionalChain(uri, doc, diagnostics))     push(actions, a);
	for (let a in addMissingImport(uri, doc, diagnostics))     push(actions, a);
	for (let a in generateJsdoc(uri, doc, range))              push(actions, a);
	for (let a in suppressDiagnostic(uri, doc, diagnostics))   push(actions, a);
	return length(actions) > 0 ? actions : null;
};
