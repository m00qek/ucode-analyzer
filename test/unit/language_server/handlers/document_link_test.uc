import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { documentLinks } from 'ucode_analyzer.language_server.handlers.document_link';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());

afterEach(() => documents.close(URI));

function links(text) {
	documents.open(URI, text, 1);
	return map(documentLinks(documents.get(URI)), (l) => ({ range: l.range, target: l.target }));
}

describe('documentLink', () => {
	it('links import sources and require() arguments to their files', () => {
		// The ranges cover the module name, inside the quotes.
		let src = cursors("import { greet } from '$1greet$2';\nlet m = require('$3legacy_mod$4');\n");
		assert.match([
			{ range: { start: src.at[1], end: src.at[2] }, target: fixture.uri('greet.uc') },
			{ range: { start: src.at[3], end: src.at[4] }, target: fixture.uri('legacy_mod.uc') },
		], links(src.text));
	});

	it('skips modules that do not resolve and non-literal requires', () => {
		assert.match([], links("import * as x from 'no.such';\nlet n = 'fs';\nrequire(n);\n"));
	});

	it('links a declaration module', () => {
		let src = cursors("import * as fs from '$1fs$2';\n");
		assert.match([
			{ range: { start: src.at[1], end: src.at[2] }, target: 'file:///app/src/ucode_analyzer/declarations/fs.d.uc' },
		], links(src.text));
	});

	it('works in a template', () => {
		assert.match([fixture.uri('greet.uc')], map(links("{% import { greet } from 'greet'; %}\n"), (l) => l.target));
	});
});
