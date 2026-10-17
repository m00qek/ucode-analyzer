import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { codeAction } from 'ucode_analyzer.language_server.handlers.code_actions';
import { preferStrictEquality } from 'ucode_analyzer.code_analysis.diagnostics.prefer_strict_equality';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// Use the actual prefer_strict_equality diagnostic to supply diagnostics,
// mirroring how a client would round-trip them back in a codeAction request.
function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('codeAction', () => {
	it('returns null when no diagnostics are supplied', () => {
		let doc = open("let x = 1 == 1;\n");
		assert.match(null, codeAction(URI, doc, []));
	});

	it('returns null when diagnostics have no severity-4 entries', () => {
		let src = cursors("$0let$1 x = 1 == 1;\n");
		let doc = open(src.text);
		let diags = [{ range: { start: src.at[0], end: src.at[1] }, severity: 1, message: 'some error' }];
		assert.match(null, codeAction(URI, doc, diags));
	});

	it('returns a quickfix action for ==', () => {
		let doc = open("let x = 1 == 2;\n");
		let diags = preferStrictEquality(doc);
		assert.match(1, length(diags));

		let actions = codeAction(URI, doc, diags);
		assert.match(true, type(actions) === 'array');
		assert.match(1, length(actions));
	});

	it('action kind is quickfix', () => {
		let doc = open("let x = 1 == 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		assert.match('quickfix', action.kind);
	});

	it('action isPreferred is true', () => {
		let doc = open("let x = 1 == 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		assert.match(true, action.isPreferred);
	});

	it('replaces == with ===', () => {
		let doc = open("let x = 1 == 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		let edit = action.edit.changes[URI][0];
		assert.match('===', edit.newText);
	});

	it('replaces != with !==', () => {
		let doc = open("let x = 1 != 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		let edit = action.edit.changes[URI][0];
		assert.match('!==', edit.newText);
	});

	it('edit range matches the diagnostic range exactly', () => {
		let src = cursors("let x = 1 $0==$1 2;\n");
		let doc = open(src.text);
		let diags = preferStrictEquality(doc);
		let action = codeAction(URI, doc, diags)[0];
		let edit = action.edit.changes[URI][0];
		assert.match(diags[0].range, edit.range);
		assert.match({ start: src.at[0], end: src.at[1] }, edit.range);
	});

	it('produces one action per operator when multiple are present', () => {
		let doc = open("let a = 1 == 2;\nlet b = 3 != 4;\n");
		let diags = preferStrictEquality(doc);
		assert.match(2, length(diags));

		let actions = codeAction(URI, doc, diags);
		assert.match(2, length(actions));
		let texts = sort(map(actions, (a) => a.edit.changes[URI][0].newText));
		assert.match('!==', texts[0]);
		assert.match('===', texts[1]);
	});

	it('action title mentions both the old and new operator', () => {
		let doc = open("let x = 1 == 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		assert.match(contains('=='), action.title);
		assert.match(contains('==='), action.title);
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("let x = 1 == 2;\n");
		let diags = preferStrictEquality(doc);
		let action = codeAction(URI, doc, diags)[0];
		assert.match(1, length(action.diagnostics));
		assert.match(diags[0].message, action.diagnostics[0].message);
	});
});
