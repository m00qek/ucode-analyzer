import { describe, it, assert, afterEach, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { parseDoc } from 'ucode_analyzer.code_analysis.types.doc_parser';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.generate_jsdoc';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);

afterEach(() => documents.close(URI));

// The inserted text for the cursor at $0, or null.
function inserted(marked) {
	let src = cursors(marked);
	documents.open(URI, src.text, 1);
	let a = actionsFor(URI, documents.get(URI), { start: src.at[0], end: src.at[0] });
	return length(a) ? a[0].edit.changes[URI][0].newText : null;
}

describe('generate_jsdoc', () => {
	it('documents each parameter and the inferred return type', () => {
		let doc = inserted("function $0add(a, b) {\n\treturn 'x';\n}\n");
		assert.match("/**\n * @param {any} a\n * @param {any} b\n * @returns {string}\n */\n", doc);
		let parsed = parseDoc(doc);
		assert.match(['a', 'b'], map(parsed.params, (p) => p.name));
		assert.match('string', parsed.returns.type.name);
	});

	it('inserts at the start of the line, with its indentation', () => {
		let doc = inserted("function f() {\n\tfunction $0g(x) { return 1; }\n}\n");
		assert.match("\t/**\n\t * @param {any} x\n\t * @returns {int}\n\t */\n", doc);
	});

	it('writes a rest parameter in the JSDoc rest form', () => {
		assert.match("/**\n * @param {any} a\n * @param {...any} r\n */\n", inserted("function $0f(a, ...r) {}\n"));
	});

	it('documents a const-assigned arrow', () => {
		assert.match(contains('@param {any} n'), inserted("const i$0nc = (n) => n;\n") ?? '');
	});

	it('is offered only on the first line of an undocumented function', () => {
		assert.match(null, inserted("/** Done. */\nfunction $0f(a) {}\n"));
		assert.match(null, inserted("function f(a) {\n\tre$0turn a;\n}\n"));
		assert.match(null, inserted("let $0x = 1;\n"));
	});

	it('skips a function with nothing to document', () => {
		assert.match(null, inserted("function $0f() {}\n"));
	});
});
