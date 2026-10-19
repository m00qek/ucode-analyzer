import { describe, it, assert, afterEach, any_order } from 'utest';
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

// The actions for doc's strict-equality diagnostics, but those that disable one.
function strictFixes(doc) {
	return filter(codeAction(URI, doc, preferStrictEquality(doc)), (a) => substr(a.title, 0, 8) !== 'Disable ');
}

// The quickfix replacing the operator at marker pair a–b of `src` with `to`.
function strictFix(src, a, b, from, to) {
	let range = { start: src.at[a], end: src.at[b] };
	return {
		title: sprintf("Replace '%s' with '%s'", from, to),
		kind: 'quickfix',
		diagnostics: [ {
			range, severity: 4, source: 'ucode-analyzer', code: 'prefer-strict-equality',
			message: sprintf("Prefer '%s' over '%s'", to, from),
		} ],
		isPreferred: true,
		edit: { changes: { [URI]: [ { range, newText: to } ] } },
	};
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
		let src = cursors("let x = 1 $0==$1 2;\n");
		let doc = open(src.text);

		assert.match([ strictFix(src, 0, 1, '==', '===') ], strictFixes(doc));
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
		let src = cursors("let a = 1 $0==$1 2;\nlet b = 3 $2!=$3 4;\n");
		let doc = open(src.text);

		assert.match(any_order([
			strictFix(src, 0, 1, '==', '==='),
			strictFix(src, 2, 3, '!=', '!=='),
		]), strictFixes(doc));
	});

	it('action title mentions both the old and new operator', () => {
		let doc = open("let x = 1 == 2;\n");
		let action = codeAction(URI, doc, preferStrictEquality(doc))[0];
		assert.match("Replace '==' with '==='", action.title);
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("let x = 1 == 2;\n");
		let diags = preferStrictEquality(doc);
		let action = codeAction(URI, doc, diags)[0];
		assert.match(diags, action.diagnostics);
	});
});
