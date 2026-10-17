import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { parseDoc } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.generate_jsdoc';

let URI = 'file:///test.uc';

dag.init({ workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src'] } });
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);

afterEach(() => documents.close(URI));

// The inserted text for the cursor at (line, character), or null.
function inserted(text, line, character) {
	documents.open(URI, text, 1);
	let a = actionsFor(URI, documents.get(URI), { start: { line, character }, end: { line, character } });
	return length(a) ? a[0].edit.changes[URI][0].newText : null;
}

describe('generate_jsdoc', () => {
	it('documents each parameter and the inferred return type', () => {
		let doc = inserted("function add(a, b) {\n\treturn 'x';\n}\n", 0, 9);
		assert.match("/**\n * @param {any} a\n * @param {any} b\n * @returns {string}\n */\n", doc);
		let parsed = parseDoc(doc);
		assert.match(['a', 'b'], map(parsed.params, (p) => p.name));
		assert.match('string', parsed.returns.type.name);
	});

	it('inserts at the start of the line, with its indentation', () => {
		let doc = inserted("function f() {\n\tfunction g(x) { return 1; }\n}\n", 1, 10);
		assert.match("\t/**\n\t * @param {any} x\n\t * @returns {int}\n\t */\n", doc);
	});

	it('writes a rest parameter in the JSDoc rest form', () => {
		assert.match("/**\n * @param {any} a\n * @param {...any} r\n */\n", inserted("function f(a, ...r) {}\n", 0, 9));
	});

	it('documents a const-assigned arrow', () => {
		assert.match(true, index(inserted("const inc = (n) => n;\n", 0, 7) ?? '', '@param {any} n') >= 0);
	});

	it('is offered only on the first line of an undocumented function', () => {
		assert.match(null, inserted("/** Done. */\nfunction f(a) {}\n", 1, 9));
		assert.match(null, inserted("function f(a) {\n\treturn a;\n}\n", 1, 3));
		assert.match(null, inserted("let x = 1;\n", 0, 4));
	});

	it('skips a function with nothing to document', () => {
		assert.match(null, inserted("function f() {}\n", 0, 9));
	});
});
