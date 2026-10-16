import { describe, it, assert, beforeEach, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import * as dag from 'code_analysis.dag.dag';
import { invalidateUri } from 'code_analysis.memo';
import { diagnosticsFor } from 'code_analysis.diagnostics';
import { documentSymbols } from 'language_server.handlers.document_symbols';
import { hover } from 'language_server.handlers.hover';
import { definition } from 'language_server.handlers.definition';
import { completion } from 'language_server.handlers.completion';
import { foldingRanges } from 'language_server.handlers.folding_range';

// Blocks left open at the end of the file, which tree-sitter closes with
// MISSING `}`s ('large open': the blocks after five complete statements).
// Every feature must behave as it does on the closed file.

let URI = 'file:///eof.uc';

let BODY   = "function f(a) {\n\tlet x = 1;\n\tif (a) {\n\t\tlet y = x;\n";
let PREFIX = "let p1 = 1;\nlet p2 = 2;\nlet p3 = 3;\nlet p4 = 4;\nlet p5 = 5;\n";

// shift: lines before BODY's first line.
let VARIANTS = [
	{ name: 'closed',     text: BODY + "\t}\n}\n", shift: 0, open: false },
	{ name: 'large open', text: PREFIX + BODY,     shift: 5, open: true  },
];

let _config = { workspaceDir: '/app', workspace: { libraryPaths: ['src'] } };

function open(text) {
	documents.open(URI, text, 1);
	dag.add(URI, text, documents.get(URI).tree);
	documents.refreshScopeMap(URI);
	return documents.get(URI);
}

function syntaxDiags(diags) {
	return filter(diags, (d) => d.code === 'syntax-error');
}

function otherDiags(diags) {
	return map(filter(diags, (d) => d.code !== 'syntax-error'),
		(d) => sprintf('%s %d:%d-%d:%d', d.code,
			d.range.start.line, d.range.start.character,
			d.range.end.line, d.range.end.character));
}

// Every syntax diagnostic is a zero-width one at `eof`; `missing` lists the
// "missing '…'" messages expected among them, in order.
function assertMissingAtEof(diags, eof, missing) {
	let syn = syntaxDiags(diags);
	for (let d in syn)
		assert.match({ start: eof, end: eof }, d.range);
	let msgs = map(filter(syn, (d) => index(d.message, 'missing') >= 0), (d) => d.message);
	assert.match(map(missing, (m) => sprintf("Syntax error: missing '%s'", m)), msgs);
}

function labelsAt(text, position) {
	return map(completion(URI, open(text), position), (i) => i.label);
}

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	invalidateUri(URI);
});

function variantSuite(v) {
	let s = v.shift;
	let eof = { line: s + 4, character: 0 };

	describe(sprintf('blocks open at EOF — %s file', v.name), () => {
		it('diagnostics report each missing } at the end of the file', () => {
			let diags = diagnosticsFor(URI, open(v.text));
			if (v.open)
				assertMissingAtEof(diags, eof, ['}', '}']);
			else
				assert.match(0, length(syntaxDiags(diags)));
		});

		it('document symbols list f with its local x', () => {
			let syms = filter(documentSymbols(open(v.text)), (x) => x.name === 'f');
			assert.match(1, length(syms));
			assert.match(12, syms[0].kind);
			assert.match(s, syms[0].range.start.line);
			assert.match(['x'], map(syms[0].children ?? [], (c) => c.name));
		});

		it('hover on x inside the innermost block shows int', () => {
			let r = hover(open(v.text), { line: s + 3, character: 10 });
			assert.match('object', type(r));
			assert.match(true, index(r.contents.value, 'int') >= 0);
		});

		it('definition of x inside the innermost block finds its let', () => {
			let r = definition(URI, open(v.text), { line: s + 3, character: 10 });
			assert.match(URI, r?.uri);
			assert.match({ line: s + 1, character: 5 }, r?.range?.start);
		});

		// Inside a block a `let` is visible from the next statement on, so the
		// innermost block's own `y` is not offered at its end, open file or not.
		it('completion at the end of the innermost block offers outer locals and parameters', () => {
			let labels = labelsAt(v.text, eof);
			assert.match([true, true], [index(labels, 'a') >= 0, index(labels, 'x') >= 0]);
		});

		it('folding ranges cover the function body and the if block', () => {
			let starts = map(foldingRanges(open(v.text)), (r) => r.startLine);
			assert.match([true, true], [index(starts, s) >= 0, index(starts, s + 2) >= 0]);
		});
	});
}

for (let v in VARIANTS)
	variantSuite(v);
