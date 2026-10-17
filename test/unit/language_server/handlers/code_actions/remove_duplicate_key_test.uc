import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.remove_duplicate_key';
import { duplicateObjectKey } from 'ucode_analyzer.code_analysis.diagnostics.duplicate_key';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('remove_duplicate_key', () => {
	it('returns empty list when no diagnostics', () => {
		let doc = open("let x = { a: 1, b: 2 };\n");
		assert.match(0, length(actionsFor(URI, doc, [])));
	});

	it('returns empty list when diagnostics have no duplicate-key code', () => {
		let src = cursors("$0l$1et x = { a: 1, a: 2 };\n");
		let doc = open(src.text);
		let diags = [{ range: { start: src.at[0], end: src.at[1] }, severity: 2, code: 'other', message: 'msg' }];
		assert.match(0, length(actionsFor(URI, doc, diags)));
	});

	it('produces a quickfix action for a duplicate key', () => {
		let doc = open("let x = { a: 1, a: 2 };\n");
		let diags = duplicateObjectKey(doc);
		assert.match(1, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(1, length(actions));
		assert.match('quickfix', actions[0].kind);
	});

	it('action title mentions the duplicate key name', () => {
		let doc = open("let x = { a: 1, a: 2 };\n");
		let diags = duplicateObjectKey(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(contains('a'), action.title);
	});

	it('action isPreferred is true', () => {
		let doc = open("let x = { a: 1, a: 2 };\n");
		let diags = duplicateObjectKey(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(true, action.isPreferred);
	});

	it('edit deletes the duplicate pair (not last in list)', () => {
		// Three pairs: a, b, a. The second 'a' is duplicate and is last.
		// Try with duplicate in middle: a, a, b
		let src = cursors("let x = { a: 1, $0a: 2, $1b: 3 };\n");
		let doc = open(src.text);
		let diags = duplicateObjectKey(doc);
		assert.match(1, length(diags));
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match('', edit.newText);
		assert.match({ start: src.at[0], end: src.at[1] }, edit.range);
	});

	it('edit deletes the duplicate pair (last in list)', () => {
		let src = cursors("let x = { a: 1, b: 2$0, a: 3$1 };\n");
		let doc = open(src.text);
		let diags = duplicateObjectKey(doc);
		assert.match(1, length(diags));
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match('', edit.newText);
		assert.match({ start: src.at[0], end: src.at[1] }, edit.range);
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("let x = { a: 1, a: 2 };\n");
		let diags = duplicateObjectKey(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(1, length(action.diagnostics));
		assert.match(diags[0].code, action.diagnostics[0].code);
	});

	it('handles multiline object — duplicate key on separate lines', () => {
		let doc = open("let x = {\n\ta: 1,\n\tb: 2,\n\ta: 3,\n};\n");
		let diags = duplicateObjectKey(doc);
		assert.match(1, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(1, length(actions));
		assert.match('', actions[0].edit.changes[URI][0].newText);
	});
});
