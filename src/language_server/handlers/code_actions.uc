import { actionsFor as preferStrictEquality } from 'language_server.handlers.code_actions.prefer_strict_equality';

export function codeAction(uri, doc, diagnostics) {
	let actions = [];
	for (let a in preferStrictEquality(uri, doc, diagnostics)) push(actions, a);
	return length(actions) > 0 ? actions : null;
};
