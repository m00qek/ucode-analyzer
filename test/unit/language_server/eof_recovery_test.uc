import { describe, it, assert, beforeEach, afterEach, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { diagnosticsFor } from 'ucode_analyzer.code_analysis.diagnostics';
import { documentSymbols } from 'ucode_analyzer.language_server.handlers.document_symbols';
import { hover } from 'ucode_analyzer.language_server.handlers.hover';
import { definition } from 'ucode_analyzer.language_server.handlers.definition';
import { completion } from 'ucode_analyzer.language_server.handlers.completion';
import { foldingRanges } from 'ucode_analyzer.language_server.handlers.folding_range';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

// Blocks left open at the end of the file. tree-sitter closes each with a
// MISSING `}`, except in a SMALL file: there one ERROR over the whole file
// costs it less, so 'tiny open' parses as a single ERROR node where 'large
// open' (the same blocks after five complete statements) gets
// program > function_declaration > … > (MISSING "}"). Every feature must
// behave on both as it does on the closed file.

let URI = 'file:///eof.uc';

// $0 a use of x in the innermost block, $1 the function, $2 the declaration
// of x, $3 the if block, $4 the end of the innermost block, $5–$6 the
// statement declaring x and $7 the end of its name, $8–$9 the name f.
let BODY   = "$1function $8f$9(a) {\n\t$5let $2x$7 = 1;$6\n\t$3if (a) {\n\t\tlet y = $0x;\n$4";
let PREFIX = "let p1 = 1;\nlet p2 = 2;\nlet p3 = 3;\nlet p4 = 4;\nlet p5 = 5;\n";

// fEnd: where f's range ends (the end of the file when open); globals: the
// other names completion offers; foldEnd: the last lines of the folds of f
// and of the if block.
let VARIANTS = [
	{ name: 'closed',     src: cursors(BODY + "\t}\n}\n"), open: false,
	  fEnd: { line: 5, character: 1 }, globals: [], foldEnd: [ 5, 4 ] },
	// a fold ends on the last line with text ...
	{ name: 'large open', src: cursors(PREFIX + BODY),     open: true,
	  globals: [ 'p1', 'p2', 'p3', 'p4', 'p5' ], foldEnd: [ 8, 8 ] },
	// ... but on the empty last line when the whole file is one ERROR
	{ name: 'tiny open',  src: cursors(BODY),              open: true,
	  globals: [], foldEnd: [ 4, 4 ] },
];

// The range from marker a to marker b of `src`.
function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

function open(text) {
	dag.add(URI, text, documents.open(URI, text, 1).tree);
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

// The completion labels other than keywords (kind 14), which are always offered.
function labelsAt(text, position) {
	return map(filter(completion(URI, open(text), position), (i) => i.kind !== 14), (i) => i.label);
}

beforeEach(() => dag.init(fixture.config()));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	invalidateUri(URI);
});

function variantSuite(v) {
	let src = v.src;
	let eof = src.at[4];

	describe(sprintf('blocks open at EOF — %s file', v.name), () => {
		it('diagnostics report each missing } at the end of the file', () => {
			let diags = diagnosticsFor(URI, open(src.text));
			if (v.open)
				assertMissingAtEof(diags, eof, ['}', '}']);
			else
				assert.match(0, length(syntaxDiags(diags)));
		});

		it('document symbols list f with its local x', () => {
			assert.match([ {
				name: 'f', kind: 12,
				range: { start: src.at[1], end: v.fEnd ?? eof },
				selectionRange: span(src, 8, 9),
				children: [ { name: 'x', kind: 13, range: span(src, 5, 6), selectionRange: span(src, 2, 7) } ],
			} ], filter(documentSymbols(open(src.text)), (x) => x.name === 'f'));
		});

		it('hover on x inside the innermost block shows int', () => {
			assert.match({ contents: { kind: 'markdown', value: "```ucode\nx: int\n```" } }, hover(open(src.text), src.at[0]));
		});

		it('definition of x inside the innermost block finds its let', () => {
			assert.match({ uri: URI, range: { start: src.at[2], end: src.at[2] } }, definition(URI, open(src.text), src.at[0]));
		});

		it('completion at the end of the innermost block offers its locals, outer locals and parameters', () => {
			let labels = labelsAt(src.text, eof);
			assert.match(any_order([ 'a', 'x', 'y', ...v.globals ]), labels);
		});

		it('folding ranges cover the function body and the if block', () => {
			assert.match(any_order([
				{ startLine: src.at[1].line, endLine: v.foldEnd[0] },
				{ startLine: src.at[3].line, endLine: v.foldEnd[1] },
			]), foldingRanges(open(src.text)));
		});
	});
}

for (let v in VARIANTS)
	variantSuite(v);

describe('blocks open at EOF — tiny file, other cases', () => {
	it('reports the same other diagnostics as the closed file, at the same ranges', () => {
		let closed = otherDiags(diagnosticsFor(URI, open(VARIANTS[0].src.text)));
		documents.close(URI);
		invalidateUri(URI);
		let tiny = otherDiags(diagnosticsFor(URI, open(VARIANTS[2].src.text)));
		assert.match(closed, tiny);
	});

	it('reports a missing end keyword for an open alt-syntax body', () => {
		let src = cursors("function f(a) {\n\tlet x = 1;\n\tif (a):\n\t\tlet y = x;\n$0");
		let doc = open(src.text);
		assertMissingAtEof(diagnosticsFor(URI, doc), src.at[0], ['endif', '}']);
		assert.match(['f'], map(documentSymbols(doc), (x) => x.name));
	});

	it('recovers a template that ends inside an open {% tag', () => {
		let src = cursors("{%\nfunction f(a) {\n\tlet x = 1;\n\tif (a) {\n\t\tlet y = x;\n$0");
		assertMissingAtEof(diagnosticsFor(URI, open(src.text)), src.at[0], ['}', '}']);
		let labels = labelsAt(src.text, src.at[0]);
		assert.match(any_order([ 'a', 'x', 'y' ]), labels);
	});

	it('ignores braces inside strings, comments and regexes', () => {
		let src = cursors("function f(a) {\n\tif (a) {\n\t\tlet s = '{';\n\t\t// {\n\t\tlet r = /{/;\n$0");
		assertMissingAtEof(diagnosticsFor(URI, open(src.text)), src.at[0], ['}', '}']);
	});
});
