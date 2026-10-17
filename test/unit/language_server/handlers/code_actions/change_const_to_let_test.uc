import { describe, it, assert, afterEach, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.change_const_to_let';
import { assignmentToConst } from 'ucode_analyzer.code_analysis.diagnostics.const_assignment';
import { cursors } from 'cursor';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// The quickfix for `diag`, turning the const at marker pair a–b of `src` into let.
function constFix(src, a, b, diag) {
	return {
		title: "Change 'const' to 'let'",
		kind: 'quickfix',
		diagnostics: [ diag ],
		isPreferred: false,
		edit: { changes: { [URI]: [ { range: { start: src.at[a], end: src.at[b] }, newText: 'let' } ] } },
	};
}

describe('change_const_to_let', () => {
	it('returns empty list when no diagnostics', () => {
		let doc = open("const x = 1;\n");
		assert.match([], actionsFor(URI, doc, []));
	});

	it('returns empty list when diagnostics have no const-assignment code', () => {
		let src = cursors("const x = 1; $0x$1 = 2;\n");
		let doc = open(src.text);
		let diags = [{ code: 'other', message: 'msg', range: { start: src.at[0], end: src.at[1] } }];
		assert.match([], actionsFor(URI, doc, diags));
	});

	it('produces a quickfix action for a const-assignment diagnostic', () => {
		let src = cursors("$0const$1 x = 1;\nx = 2;\n");
		let doc = open(src.text);
		let diags = assignmentToConst(doc);
		assert.match(1, length(diags));
		assert.match([ constFix(src, 0, 1, diags[0]) ], actionsFor(URI, doc, diags));
	});

	it('action title says Change const to let', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match("Change 'const' to 'let'", action.title);
	});

	it('action isPreferred is false (prefer fixing the assignment instead)', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(false, action.isPreferred);
	});

	it('edit replaces the const keyword with let', () => {
		let src = cursors("$0const$1 x = 1;\nx = 2;\n");
		let doc = open(src.text);
		let diags = assignmentToConst(doc);
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match('let', edit.newText);
		assert.match({ start: src.at[0], end: src.at[1] }, edit.range);
	});

	it('deduplicates: two assignments to same const produce one action', () => {
		let src = cursors("$0const$1 x = 1;\nx = 2;\nx = 3;\n");
		let doc = open(src.text);
		let diags = assignmentToConst(doc);
		assert.match(2, length(diags));
		// the action carries the first of the two diagnostics
		assert.match([ constFix(src, 0, 1, diags[0]) ], actionsFor(URI, doc, diags));
	});

	it('produces separate actions for two different const variables', () => {
		let src = cursors("$0const$1 x = 1;\n$2const$3 y = 2;\nx = 3;\ny = 4;\n");
		let doc = open(src.text);
		let diags = assignmentToConst(doc);
		assert.match(2, length(diags));
		assert.match(any_order([ constFix(src, 0, 1, diags[0]), constFix(src, 2, 3, diags[1]) ]), actionsFor(URI, doc, diags));
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("const x = 1;\nx = 2;\n");
		let diags = assignmentToConst(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(diags, action.diagnostics);
		assert.match('const-assignment', action.diagnostics[0].code);
	});
});
