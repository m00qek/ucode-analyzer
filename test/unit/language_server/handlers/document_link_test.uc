import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { documentLinks } from 'ucode_analyzer.language_server.handlers.document_link';

let URI = 'file:///test.uc';

dag.init({ workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src', 'test'] } });

afterEach(() => documents.close(URI));

function links(text) {
	documents.open(URI, text, 1);
	return map(documentLinks(documents.get(URI)), (l) =>
		[l.range.start.line, l.range.start.character, l.range.end.character, l.target]);
}

describe('documentLink', () => {
	it('links import sources and require() arguments to their files', () => {
		let text = "import { greet } from 'fixtures.greet';\nlet m = require('fixtures.legacy_mod');\n";
		// The ranges cover the module name, inside the quotes.
		let a = index(text, 'fixtures.greet'), b = index("let m = require('fixtures.legacy_mod');", 'fixtures.legacy_mod');
		assert.match([
			[0, a, a + length('fixtures.greet'), 'file:///app/test/fixtures/greet.uc'],
			[1, b, b + length('fixtures.legacy_mod'), 'file:///app/test/fixtures/legacy_mod.uc'],
		], links(text));
	});

	it('skips modules that do not resolve and non-literal requires', () => {
		assert.match([], links("import * as x from 'no.such';\nlet n = 'fs';\nrequire(n);\n"));
	});

	it('links a declaration module', () => {
		assert.match([[0, 21, 23, 'file:///app/src/ucode_analyzer/declarations/fs.d.uc']], links("import * as fs from 'fs';\n"));
	});

	it('works in a template', () => {
		assert.match(1, length(links("{% import { greet } from 'fixtures.greet'; %}\n")));
	});
});
