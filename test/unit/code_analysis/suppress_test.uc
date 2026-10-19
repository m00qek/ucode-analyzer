import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { diagnosticsFor } from 'ucode_analyzer.code_analysis.diagnostics';
import { codeAction } from 'ucode_analyzer.language_server.handlers.code_actions';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);

afterEach(() => documents.close(URI));

// [line, code] of every diagnostic of text but style hints.
function found(text) {
	documents.open(URI, text, 1);
	return map(filter(diagnosticsFor(URI, documents.get(URI)), (d) => d.code !== 'prefer-strict-equality'),
		(d) => [ d.range.start.line, d.code ]);
}

describe('suppression comments', () => {
	it('disable-next-line hides the next line, disable its own', () => {
		assert.match([ [ 0, 'undefined-var' ], [ 3, 'undefined-var' ] ],
			found("print(a);\n// ucode-analyzer disable-next-line\nprint(b);\nprint(c);\nprint(d); // ucode-analyzer disable\n"));
	});

	it('limits a directive to the codes it names, before a reason', () => {
		assert.match([ [ 1, 'undefined-var' ] ],
			found("// ucode-analyzer disable-next-line unused-var, may-be-null -- not ours\nlet x = a;\n"));
		assert.match([],
			found("// ucode-analyzer disable-next-line unused-var undefined-var -- generated\nlet x = a;\n"));
	});

	it('reads block comments and template comments, not strings or other words', () => {
		assert.match([], found("/* ucode-analyzer disable-next-line */\nprint(a);\n"));
		assert.match([], found("<p>{# ucode-analyzer disable-next-line #}\n{{ a }}</p>\n"));
		assert.match([ [ 1, 'undefined-var' ] ], found("let s = '// ucode-analyzer disable-next-line';\nprint(s, a);\n"));
		assert.match([ [ 1, 'undefined-var' ] ], found("// ucode-analyzer disabled\nprint(a);\n"));
	});

	it('offers a quick fix that writes the directive above the line', () => {
		documents.open(URI, "function f() {\n\tprint(a);\n}\n", 1);
		let doc = documents.get(URI);
		let d = filter(diagnosticsFor(URI, doc), (d) => d.code === 'undefined-var');
		let fix = filter(codeAction(URI, doc, d, null) ?? [], (a) => a.title === 'Disable undefined-var for this line');
		assert.match([ { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
			newText: "\t// ucode-analyzer disable-next-line undefined-var\n" } ], fix[0]?.edit?.changes?.[URI]);
	});
});
