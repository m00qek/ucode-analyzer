import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.remove_unused_import';
import { unusedImports } from 'ucode_analyzer.code_analysis.diagnostics.unused_imports';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('remove_unused_import', () => {
	it('returns empty list when no diagnostics', () => {
		let doc = open("import { x } from 'mod';\nx;\n");
		assert.match(0, length(actionsFor(URI, doc, [])));
	});

	it('returns empty list when diagnostics have no unused-import code', () => {
		let doc = open("import { x } from 'mod';\n");
		let diags = [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
		               severity: 1, code: 'some-other-code', message: 'err' }];
		assert.match(0, length(actionsFor(URI, doc, diags)));
	});

	it('produces a quickfix action for an unused namespace import', () => {
		let doc = open("import * as ts from 'tree_sitter';\nlet x = 1;\n");
		let diags = unusedImports(doc);
		assert.match(1, length(diags));
		let actions = actionsFor(URI, doc, diags);
		assert.match(1, length(actions));
		assert.match('quickfix', actions[0].kind);
	});

	it('action title mentions the unused name', () => {
		let doc = open("import * as ts from 'tree_sitter';\nlet x = 1;\n");
		let diags = unusedImports(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(true, index(action.title, 'ts') >= 0);
	});

	it('action isPreferred is true', () => {
		let doc = open("import * as ts from 'tree_sitter';\nlet x = 1;\n");
		let diags = unusedImports(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(true, action.isPreferred);
	});

	it('edit removes the entire import line for a namespace import', () => {
		let doc = open("import * as ts from 'tree_sitter';\nlet x = 1;\n");
		let diags = unusedImports(doc);
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.start.character);
		assert.match(1, edit.range.end.line);
		assert.match(0, edit.range.end.character);
		assert.match('', edit.newText);
	});

	it('edit removes the entire import line for a single named import', () => {
		let doc = open("import { foo } from 'mod';\nlet x = 1;\n");
		let diags = unusedImports(doc);
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.start.character);
		assert.match(1, edit.range.end.line);
		assert.match('', edit.newText);
	});

	it('removes only the unused specifier when multiple named imports exist', () => {
		let doc = open("import { foo, bar } from 'mod';\nbar;\n");
		let diags = unusedImports(doc);
		assert.match(1, length(diags));
		assert.match('foo', index(diags[0].message, 'foo') >= 0 ? 'foo' : '?');
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		// Should delete 'foo, ' (i.e. stay on line 0, not remove the whole line)
		assert.match(0, edit.range.start.line);
		assert.match(0, edit.range.end.line);
		assert.match('', edit.newText);
	});

	it('removes trailing specifier leaving earlier ones intact', () => {
		let doc = open("import { foo, bar } from 'mod';\nfoo;\n");
		let diags = unusedImports(doc);
		assert.match(1, length(diags));
		let edit = actionsFor(URI, doc, diags)[0].edit.changes[URI][0];
		// Should delete ', bar' (same line, non-zero start character)
		assert.match(0, edit.range.start.line);
		assert.match(true, edit.range.start.character > 0);
		assert.match('', edit.newText);
	});

	it('action carries back the originating diagnostic', () => {
		let doc = open("import { foo } from 'mod';\n");
		let diags = unusedImports(doc);
		let action = actionsFor(URI, doc, diags)[0];
		assert.match(1, length(action.diagnostics));
		assert.match(diags[0].code, action.diagnostics[0].code);
	});
});
