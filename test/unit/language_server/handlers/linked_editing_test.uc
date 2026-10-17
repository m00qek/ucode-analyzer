import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { linkedEditingRanges } from 'ucode_analyzer.language_server.handlers.linked_editing';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

function at(text, line, character) {
	documents.open(URI, text, 1);
	let r = linkedEditingRanges(documents.get(URI), { line, character });
	return r ? map(r.ranges, (x) => [x.start.line, x.start.character, x.end.line, x.end.character]) : null;
}

describe('linkedEditingRange', () => {
	let FOR = "for (k in o):\n  y();\nendfor\n";

	it('links `for` with the `for` of `endfor`', () => {
		assert.match([[0, 0, 0, 3], [2, 3, 2, 6]], at(FOR, 0, 1));
	});

	it('answers from the closing keyword too', () => {
		assert.match([[0, 0, 0, 3], [2, 3, 2, 6]], at(FOR, 2, 4));
	});

	it('answers nothing inside the block', () => {
		assert.match(null, at(FOR, 1, 2));
	});

	it('covers while, if without else, and the colon-form function', () => {
		let w = "while (b): z(); endwhile\n", e = index(w, 'endwhile') + 3;
		assert.match([[0, 0, 0, 5], [0, e, 0, e + 5]], at(w, 0, 2));
		assert.match([[0, 0, 0, 2], [2, 3, 2, 5]], at("if (a):\n  x();\nendif\n", 0, 0));
		let f = "function f(): return 1; endfunction\n", g = index(f, 'endfunction') + 3;
		assert.match([[0, 0, 0, 8], [0, g, 0, g + 8]], at(f, 0, 3));
	});

	it('works inside template tags', () => {
		assert.match([[0, 3, 0, 8], [0, 23, 0, 28]], at("{% while (b): %}x{% endwhile %}\n", 0, 4));
	});

	it('leaves out an if with else or elif, a missing closer, and braces', () => {
		assert.match(null, at("if (a):\n  x();\nelse\n  y();\nendif\n", 0, 0));
		assert.match(null, at("if (a):\n  x();\nelif (b):\n  y();\nendif\n", 0, 0));
		assert.match(null, at("if (a):\n  x();\n", 0, 0));
		assert.match(null, at("if (a) {\n  x();\n}\n", 0, 0));
	});
});
