import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_language_server.documents';
import { hover } from 'ucode_language_server.handlers.hover';
import { invalidateUri } from 'ucode_language_server.memo';
import * as dag from 'ucode_language_server.dag.dag';
import * as templates from 'ucode_language_server.templates';

let URI = 'file:///test.uc';

let _config = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] } };
// Config with selfSrcDir so hover uses the built-in templates (not the fallback).
let _full_config = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] }, selfSrcDir: '/app/src' };

dag.init(_config);

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
	templates.resetCache();
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

describe('hover — via templates (selfSrcDir set)', () => {
	let TS_URI = 'file:///app/src/tree_sitter.uc';

	it('function hover renders declaration-form signature and Parameters section', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts.parse;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		dag.add(URI, doc.text, doc.tree);

		// line 1, character 3 → 'parse' property_identifier
		let result = hover(doc, { line: 1, character: 3 }, _full_config);

		assert.match('object', type(result));
		// Signature is declaration-form, not type-annotation form.
		assert.match(true, index(result.contents.value, 'function parse(') >= 0);
		assert.match(true, index(result.contents.value, '**Parameters:**') >= 0);
		// Each param must be on its own line.
		assert.match(true, index(result.contents.value, '\n- `') >= 0);
	});

	it('module hover renders module specifier from module template', () => {
		dag.addFromDisk(TS_URI);
		let text = "import * as ts from 'tree_sitter';\nts;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		dag.add(URI, doc.text, doc.tree);

		// line 1, character 0 → 'ts' namespace alias
		let result = hover(doc, { line: 1, character: 0 }, _full_config);

		assert.match('object', type(result));
		// module template uses "module 'specifier'" format
		assert.match(true, index(result.contents.value, "module 'tree_sitter'") >= 0);
	});

	it('default hover renders code fence for primitive type', () => {
		let text = "let x = 42;";
		documents.open(URI, text, 1);
		let doc = documents.get(URI);
		dag.add(URI, doc.text, doc.tree);

		let result = hover(doc, { line: 0, character: 4 }, _full_config);

		assert.match('object', type(result));
		assert.match(true, index(result.contents.value, 'x') >= 0);
		assert.match(true, index(result.contents.value, 'int') >= 0);
	});
});
