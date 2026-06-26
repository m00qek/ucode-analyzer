import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { hover } from 'ucode_language_server.handlers.hover';
import { invalidateUri } from 'ucode_language_server.memo';
import * as dag from 'ucode_language_server.dag.dag';

let URI = 'file:///test.uc';

let _config = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] } };
dag.init(_config);

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
});

describe('hover', () => {
	it('returns inferred type for an identifier', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 4 is 'x'; buildScope processes the declaration → x: int
		let result = hover(doc, { line: 0, character: 4 });

		assert.match('object', type(result));
		assert.match('markdown', result.contents.kind);
		assert.match(true, index(result.contents.value, 'x') >= 0);
		assert.match(true, index(result.contents.value, 'int') >= 0);
	});

	it('returns inferred type for an integer literal', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 8 is the '5' literal
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(true, index(result.contents.value, 'int') >= 0);
	});

	it('returns inferred type for a string literal', () => {
		documents.open(URI, "let s = 'hello';", 1);
		let doc = documents.get(URI);

		// character 8 is the opening quote of 'hello'
		let result = hover(doc, { line: 0, character: 8 });

		assert.match('object', type(result));
		assert.match(true, index(result.contents.value, 'string') >= 0);
	});

	it('returns null for an anonymous token with no inferable type', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		// character 0 is 'l' in 'let'; nodeAtOffset returns lexical_declaration → unknown
		let result = hover(doc, { line: 0, character: 0 });

		assert.match(null, result);
	});

	it('returns null when position is beyond end of file', () => {
		documents.open(URI, 'let x = 5;', 1);
		let doc = documents.get(URI);

		assert.match(null, hover(doc, { line: 99, character: 0 }));
	});

});

describe('hover — property_identifier in member expression', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	// `import * as ts from 'tree_sitter'; ts.parse;`
	// Hovering on 'parse' (property_identifier) should include its JSDoc, not just the type.
	it('shows JSDoc for a property of a namespace-import module', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts.parse;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		// Register the document in the DAG so importsOf resolves the namespace import.
		dag.add(URI, doc.text, doc.tree);
		// line 1, character 3 → 'p' of 'parse'
		let result = hover(doc, { line: 1, character: 3 });
		assert.match('object', type(result));
		// type string contains the name and signature
		assert.match(true, index(result.contents.value, 'parse') >= 0);
		// JSDoc description is rendered (not just the type string)
		assert.match(true, index(result.contents.value, 'Parse source text') >= 0);
	});
});
