import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { nanArithmetic } from 'ucode_analyzer.code_analysis.diagnostics.nan_arithmetic';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);

afterEach(() => documents.close(URI));

function messages(text) {
	documents.open(URI, text, 1);
	return map(nanArithmetic(URI, documents.get(URI)), (d) => d.message);
}

describe('diagnostics — arithmetic that is NaN', () => {
	it('flags the operand, at it', () => {
		let src = cursors("let parts = split('a.b', '.');\nlet n = $0parts$1 - 1;\n");
		documents.open(URI, src.text, 1);
		assert.match([{
			range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
			code: 'nan-arithmetic', message: "'parts' is an array: '-' on it is NaN",
		}], nanArithmetic(URI, documents.get(URI)));
	});

	it('flags a string literal that is not a number, objects and functions', () => {
		assert.match([ "'abc' is not a number: '*' on it is NaN" ], messages("let n = 'abc' * 2;\n"));
		assert.match([ "'o' is an object: '/' on it is NaN" ], messages("let o = { a: 1 };\nlet n = 10 / o;\n"));
		assert.match([ "'f' is a function: '%' on it is NaN" ], messages("function f() {}\nlet n = f % 2;\n"));
	});

	it('accepts numbers, numeric strings, + and values it cannot be sure of', () => {
		assert.match([], messages("let s = '5', a = [1], x;\nlet n = '5' * 2 + ' 1.5e3 ' / 3 - s * 2 + x * 2;\nlet t = a + 'x';\n"));
		assert.match([], messages("/** @param {?array} a */\nfunction f(a) { return a ? 1 : length(a) - 1; }\n"));
	});
});
