import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { unknownTypes } from 'ucode_analyzer.code_analysis.diagnostics.unknown_type';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
});

// The unknown-type diagnostics of text, indexed so its typedefs are known.
function diags(text) {
	documents.open(URI, text, 1);
	dag.add(URI, text, documents.get(URI).tree);
	return unknownTypes(documents.get(URI));
}

describe('diagnostics — unknown JSDoc type names', () => {
	it('flags a name no @typedef defines, at the name', () => {
		let src = cursors("/** @param {$0Conf$1} c */\nfunction f(c) {}\n");
		assert.match([{
			range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
			code: 'unknown-type', message: "Unknown type 'Conf': no @typedef defines it",
		}], diags(src.text));
	});

	it('suggests the name a JavaScript spelling or a case slip stands for', () => {
		assert.match([ "Unknown type 'RegExp': did you mean 'regexp'?" ],
			map(diags("/** @param {RegExp} r */\nfunction f(r) {}\n"), (d) => d.message));
		assert.match([ "Unknown type 'conf': did you mean 'Conf'?" ],
			map(diags("/**\n * @typedef {Object} Conf\n * @property {string} name\n */\n/** @returns {?conf} */\nfunction f() {}\n"),
				(d) => d.message));
	});

	it('knows typedefs, template parameters, Array and Object, and builtins', () => {
		assert.match([], diags("/**\n * @typedef {Object} Conf\n * @property {string} name\n */\n" +
			"/**\n * @template T\n * @param {Conf} c\n * @param {Array<T>} xs\n * @param {Object<string, int>} m\n" +
			" * @param {?(string|regexp)} s\n * @returns {list<T>}\n */\nfunction f(c, xs, m, s) {}\n"));
	});

	it('looks inside the types around a name', () => {
		assert.match([ "Unknown type 'Item': no @typedef defines it" ],
			map(diags("/** @param {list<?Item>} xs */\nfunction f(xs) {}\n"), (d) => d.message));
	});
});
