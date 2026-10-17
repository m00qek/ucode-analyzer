import { describe, it, assert, beforeEach, afterEach, contains } from 'utest';
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
// of x, $3 the if block, $4 the end of the innermost block.
let BODY   = "$1function f(a) {\n\tlet $2x = 1;\n\t$3if (a) {\n\t\tlet y = $0x;\n$4";
let PREFIX = "let p1 = 1;\nlet p2 = 2;\nlet p3 = 3;\nlet p4 = 4;\nlet p5 = 5;\n";

let VARIANTS = [
	{ name: 'closed',     src: cursors(BODY + "\t}\n}\n"), open: false },
	{ name: 'large open', src: cursors(PREFIX + BODY),     open: true  },
	{ name: 'tiny open',  src: cursors(BODY),              open: true  },
];

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

function labelsAt(text, position) {
	return map(completion(URI, open(text), position), (i) => i.label);
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
			let syms = filter(documentSymbols(open(src.text)), (x) => x.name === 'f');
			assert.match(1, length(syms));
			assert.match(12, syms[0].kind);
			assert.match(src.at[1], syms[0].range.start);
			assert.match(['x'], map(syms[0].children ?? [], (c) => c.name));
		});

		it('hover on x inside the innermost block shows int', () => {
			let r = hover(open(src.text), src.at[0]);
			assert.match('object', type(r));
			assert.match(contains('int'), r.contents.value);
		});

		it('definition of x inside the innermost block finds its let', () => {
			let r = definition(URI, open(src.text), src.at[0]);
			assert.match(URI, r?.uri);
			assert.match(src.at[2], r?.range?.start);
		});

		it('completion at the end of the innermost block offers its locals, outer locals and parameters', () => {
			let labels = labelsAt(src.text, eof);
			assert.match([true, true, true], map(['a', 'x', 'y'], (n) => index(labels, n) >= 0));
		});

		it('folding ranges cover the function body and the if block', () => {
			let starts = map(foldingRanges(open(src.text)), (r) => r.startLine);
			assert.match([true, true], [index(starts, src.at[1].line) >= 0, index(starts, src.at[3].line) >= 0]);
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
		assert.match([true, true], [index(labels, 'a') >= 0, index(labels, 'x') >= 0]);
	});

	it('ignores braces inside strings, comments and regexes', () => {
		let src = cursors("function f(a) {\n\tif (a) {\n\t\tlet s = '{';\n\t\t// {\n\t\tlet r = /{/;\n$0");
		assertMissingAtEof(diagnosticsFor(URI, open(src.text)), src.at[0], ['}', '}']);
	});
});
