import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { inlayHints } from 'ucode_analyzer.language_server.handlers.inlay_hints';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = 'file:///test.uc';

dag.init(fixture.config());

// Full-file range helper.
function fullRange() {
	return { start: { line: 0, character: 0 }, end: { line: 9999, character: 0 } };
}

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

// A type hint (kind 1) at `position`.
function typeHint(position, label) {
	return { position, label, kind: 1, paddingLeft: true };
}

// A parameter-name hint (kind 2) at `position`.
function paramHint(position, label) {
	return { position, label, kind: 2, paddingRight: true };
}

afterEach(() => {
	documents.close(URI);
	invalidateUri(URI);
});

// ---------- Variable type hints ----------

describe('inlayHints — variable type hints', () => {
	it('emits a type hint for a function-call initializer', () => {
		// makeStr has a known return type (string); the hint should appear.
		let src = cursors("function makeStr() { return 'hello'; }\nlet y$0 = makeStr();\n");
		assert.match([ typeHint(src.at[0], ': string') ], inlayHints(open(src.text), fullRange()));
	});

	it('does not emit a hint for a number literal', () => {
		let doc = open("let x = 42;\n");
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('does not emit a hint for a string literal', () => {
		let doc = open('let x = "hello";\n');
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('does not emit a hint for a boolean literal', () => {
		let doc = open("let x = true;\n");
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('does not emit a hint for a null literal', () => {
		let doc = open("let x = null;\n");
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('does not emit a hint when inference yields unknown', () => {
		let doc = open("let x = undefined_function();\n");
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('abbreviates function-typed variables to fn', () => {
		// A variable assigned to a known function reference has type 'function'.
		let src = cursors("function greet() {}\nlet h$0 = greet;\n");
		assert.match([ typeHint(src.at[0], ': fn') ], inlayHints(open(src.text), fullRange()));
	});

	it('hint position is at the end of the variable name', () => {
		let src = cursors("function makeStr() { return 'x'; }\nlet z$0 = makeStr();\n");
		assert.match([ typeHint(src.at[0], ': string') ], inlayHints(open(src.text), fullRange()));
	});

	it('hint has kind 1 (Type) and paddingLeft', () => {
		let src = cursors("function makeStr() { return 'x'; }\nlet y$0 = makeStr();\n");
		assert.match([ { position: src.at[0], label: ': string', kind: 1, paddingLeft: true } ], inlayHints(open(src.text), fullRange()));
	});

	it('respects range: excludes hints outside the requested range', () => {
		// the range is the line of `a`; `b` starts where it ends
		let src = cursors("function makeStr() { return 'x'; }\n$0let a$2 = makeStr();\n$1let b = makeStr();\n");
		let range = { start: src.at[0], end: src.at[1] };
		assert.match([ typeHint(src.at[2], ': string') ], inlayHints(open(src.text), range));
	});
});

// ---------- Parameter name hints ----------

describe('inlayHints — parameter name hints', () => {
	it('emits a parameter hint for a documented function call', () => {
		let src = cursors("/**\n * @param {int} x\n * @param {int} y\n */\nfunction add(x, y) { return x + y; }\nadd($01, $12);\n");
		assert.match([ paramHint(src.at[0], 'x:'), paramHint(src.at[1], 'y:') ], inlayHints(open(src.text), fullRange()));
	});

	it('hint has kind 2 (Parameter) and paddingRight', () => {
		let src = cursors("/**\n * @param {int} x\n */\nfunction f(x) { return x; }\nf($042);\n");
		assert.match([ { position: src.at[0], label: 'x:', kind: 2, paddingRight: true } ], inlayHints(open(src.text), fullRange()));
	});

	it('hint position is at the start of the argument', () => {
		let src = cursors("/**\n * @param {int} x\n */\nfunction f(x) { return x; }\nf($042);\n");
		assert.match([ paramHint(src.at[0], 'x:') ], inlayHints(open(src.text), fullRange()));
	});

	it('skips hint when argument identifier matches param name', () => {
		let doc = open("/**\n * @param {int} x\n */\nfunction f(x) { return x; }\nlet x = 1;\nf(x);\n");
		// `let x = 1` gets no type hint either: literal initializers never do
		assert.match([], inlayHints(doc, fullRange()));
	});

	it('emits no hints for a call to a builtin', () => {
		// Current behaviour: no parameter names and no type hint for x, though
		// global.d.uc documents split(str, sep, limit) as returning Array<string>.
		let doc = open("let x = split('a,b', ',');\n");
		assert.match([], inlayHints(doc, fullRange()));
	});
});
