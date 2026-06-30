import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'language_server.documents';
import { actionsFor } from 'language_server.handlers.code_actions.change_const_to_let';
import { assignmentToConst } from 'language_server.handlers.diagnostics.assignment_const';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('change_const_to_let', () => {
	it('returns empty list when no diagnostics', () => {
		let doc = open("const x = 1;\n");
		assert.match(0, length(actionsFor(URI, doc, [])));
	});

	it('returns empty list when diagnostics have no const-assignment code', () => {
		let doc = open("const x = 1; x = 2;\n");
		let diags = [{ code: 'other', message: 'msg',
		               range: { start: { line: 0, character: 13 }, end: { line: 0, character: 14 } } }];
		assert.match(0, length(actionsFor(URI, doc, diags)));
	});

	it('produces a quickfix action for a const-assignment diagnostic', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		assert.match(1, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(1, length(actions));
		assert.match('quickfix', actions[0].kind);
	});

	it('action title says Change const to let', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(true, index(action.title, 'const') >= 0);
		assert.match(true, index(action.title, 'let') >= 0);
	});

	it('action isPreferred is false (prefer fixing the assignment instead)', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(false, action.isPreferred);
	});

	it('edit replaces the const keyword with let', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match('let', edit.newText);
		// const keyword is at line 0, character 0
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.start.character);
	});

	it('deduplicates: two assignments to same const produce one action', () => {
		let doc = open("const x = 1;\nx = 2;\nx = 3;\n");
		let diags = assignmentToConst(doc);
		assert.match(2, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(1, length(actions));
	});

	it('produces separate actions for two different const variables', () => {
		let doc = open("const x = 1;\nconst y = 2;\nx = 3;\ny = 4;\n");
		let diags = assignmentToConst(doc);
		assert.match(2, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(2, length(actions));
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(1, length(action.diagnostics));
		assert.match('const-assignment', action.diagnostics[0].code);
	});
});
