import { actionsFor as preferStrictEquality } from 'language_server.handlers.code_actions.prefer_strict_equality';
import { actionsFor as removeUnusedImport }   from 'language_server.handlers.code_actions.remove_unused_import';
import { actionsFor as removeDuplicateKey }   from 'language_server.handlers.code_actions.remove_duplicate_key';
import { actionsFor as changeConstToLet }     from 'language_server.handlers.code_actions.change_const_to_let';

export function codeAction(uri, doc, diagnostics) {
	let actions = [];
	for (let a in preferStrictEquality(uri, doc, diagnostics)) push(actions, a);
	for (let a in removeUnusedImport(uri, doc, diagnostics))   push(actions, a);
	for (let a in removeDuplicateKey(uri, doc, diagnostics))   push(actions, a);
	for (let a in changeConstToLet(uri, doc, diagnostics))     push(actions, a);
	return length(actions) > 0 ? actions : null;
};
