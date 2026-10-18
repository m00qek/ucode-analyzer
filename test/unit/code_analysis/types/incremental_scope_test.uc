import { describe, it, assert, afterEach } from 'utest';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { buildScopeMap, lastBuildStats } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { mapDifference } from 'ucode_analyzer.code_analysis.types.type_eq';
import { typeErrors } from 'ucode_analyzer.code_analysis.diagnostics.type_errors';
import { definition } from 'ucode_analyzer.language_server.handlers.definition';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import * as fixture from 'fixture';

dag.init(fixture.config());
let _globalUri = dag.resolveSpecifier('global');
if (_globalUri) {
	dag.addFromDisk(_globalUri);
	initBuiltinsFromDag(_globalUri);
}

let URI = fixture.uri('test_incremental.uc');
let _version = 1;

afterEach(() => {
	documents.checkIncremental(false);
	documents.close(URI);
});

// How the document's scope map differs from one built from scratch, or null.
function differs() {
	let doc = documents.get(URI);
	let full = buildScopeMap(URI, doc.text, doc.tree);
	let d = mapDifference(doc.scopeMap, full);
	if (d) return d;
	let e1 = sprintf('%J', typeErrors(URI, doc)), e2 = sprintf('%J', typeErrors(URI, { ...doc, scopeMap: full }));
	return (e1 === e2) ? null : sprintf('diagnostics %s vs %s', e1, e2);
}

function open(text) {
	documents.open(URI, text, _version++);
	documents.get(URI);
}

// Replace the first `from` of the document's text with `to`; the new map's
// { reused, walked } units.
function edit(from, to) {
	let text = documents.peek(URI).text;
	let at = index(text, from);
	assert.match(true, at >= 0, from);
	text = substr(text, 0, at) + to + substr(text, at + length(from));
	dag.update(URI, text, documents.change(URI, [ { text } ], _version++).tree, documents.all());
	documents.get(URI);
	let st = lastBuildStats();
	return { reused: st.reused, walked: st.walked };
}

// Five functions, the third keeping a top-level variable's value.
const FIVE = "let limit = 10;\n" +
	"function a(x) { let y = x + 1; return y; }\n" +
	"function b(s) { if (s == null) return ''; return s; }\n" +
	"function c(n) { let m = limit; return n > m ? m : n; }\n" +
	"function d(o) { let k = keys(o ?? {}); return k; }\n" +
	"function e() { return [ 1, 2 ]; }\n";

// Give the y of function a, in the checkpoints the next map reuses, a type it
// does not have.
function corruptY() {
	let built = documents.peek(URI).built;
	let u = built.units[0];
	for (let i = u.first; i < u.last; i++)
		for (let s = built.map[i].scope; s; s = s.parent)
			if (exists(s.bindings, 'y')) s.bindings.y = { kind: 'corrupt' };
}

describe('incremental scope map', () => {
	it('reuses the functions an edit within one line does not touch', () => {
		open(FIVE);
		assert.match({ reused: 4, walked: 1 }, edit('x + 1', 'x + 2'));
		assert.match(null, differs());
	});

	it('walks again a function reading what the edit changed', () => {
		open(FIVE);
		// c's m holds limit's type; the others do not read it.
		assert.match({ reused: 4, walked: 1 }, edit('let limit = 10;', "let limit = 'a';"));
		assert.match(null, differs());
	});

	it('reuses the functions after an edit that adds a line', () => {
		open(FIVE);
		assert.match({ reused: 4, walked: 1 }, edit('let m = limit;', 'let m = limit;\n'));
		assert.match(null, differs());
	});

	it('moves the places a reused function holds with the edit', () => {
		// o's record holds where its field is, which go-to-definition reads.
		open("function a() { return 1; }\nfunction make() { let o = { port: 1 }; return o.port; }\n");
		assert.match({ reused: 1, walked: 1 }, edit('return 1;', 'return 1;\n\n'));
		assert.match(null, differs());
		let doc = documents.get(URI);
		let r = definition(URI, doc, offsetToPosition(doc.text, doc.lineTable, index(doc.text, 'o.port') + 2));
		assert.match(offsetToPosition(doc.text, doc.lineTable, index(doc.text, 'port: 1')), r?.range?.start);
	});

	it('walks again a function whose own text the edit is in, and its new parameters', () => {
		open("/** @param {string} s */\nfunction f(s) { let t = s; return t; }\nfunction g() { return 1; }\n");
		assert.match({ reused: 1, walked: 1 }, edit('{string}', '{int}'));
		assert.match(null, differs());
	});

	it('walks again the functions seeing a captured variable an edit assigns anew', () => {
		open("let x = null;\nfunction set() { x = 1; }\nfunction get() { return x + 1; }\nfunction other() { return 2; }\n");
		let st = edit('x = 1;', "x = 'a';");
		assert.match(true, st.walked >= 2, st);
		assert.match(null, differs());
	});

	it('walks again a function whose closures see a captured variable an edit assigns anew', () => {
		// Captured variables are matched by name: set's closure assigns an x,
		// which use's closure f sees in its own x.
		open("function set() { let x = 0; let g = () => { x = 1; }; return g; }\n" +
			"function use() { let x = null; let h = () => { x = {}; }; let f = () => { let y = x; return y; }; return f; }\n");
		assert.match({ reused: 0, walked: 2 }, edit('x = 1;', "x = 'a';"));
		assert.match(null, differs());
	});

	it('infers a captured variable when a full build would, not when checking a function', () => {
		// waiting's type is first inferred at f, where g is declared; at the
		// start of make it is not yet.
		open("function make() {\n\tlet waiting = [];\n\tlet g = 1;\n\tlet f = () => waiting;\n" +
			"\tlet h = () => { waiting = g; };\n\treturn [ f, h ];\n}\nfunction other() { return 1; }\n");
		assert.match({ reused: 1, walked: 1 }, edit('return 1;', 'return 2;'));
		assert.match(null, differs());
	});

	it('replays the optional-chain roots a reused function declares', () => {
		// They are matched by name: f's `code` is b's chain, and so is g's.
		open("function f(b) { let code = b?.s?.c; return code; }\n" +
			"/** @param {?object} b */\nfunction g(b, code) {\n\tif (code == null) return;\n\tlet t = b;\n\treturn t;\n}\n");
		assert.match({ reused: 1, walked: 1 }, edit('let t = b;', 'let t = b; '));
		assert.match(null, differs());
	});

	it('walks again a function reading an optional-chain root an edit removes', () => {
		// g's code is b's chain while f declares it so: then the guard narrows b.
		open("function f(b) { let code = b?.s?.c; return code; }\n" +
			"/** @param {?object} b */\nfunction g(b, code) {\n\tif (code == null) return;\n\tlet t = b;\n\treturn t;\n}\n");
		assert.match({ reused: 0, walked: 2 }, edit('let code = b?.s?.c;', 'let code = 1;'));
		assert.match(null, differs());
	});

	it('walks again a function that inferred a captured variable first, once an earlier one does', () => {
		// x's type is inferred where it is first assigned in a closure: in a,
		// before v is declared, it does not see v.
		open("function a() { let y = null; return y; }\nlet v = 5;\n" +
			"function b() { let x = null; let s = () => { x = v; }; return s; }\n");
		assert.match({ reused: 0, walked: 2 }, edit('let y = null; return y;', 'let x = null; let s = () => { x = v; }; return s;'));
		assert.match(null, differs());
	});

	it('builds afresh after an edit to a @typedef', () => {
		open("/**\n * @typedef {Object} P\n * @property {string} n\n */\nfunction f(/** P */ p) { return p.n; }\nfunction g() { return 1; }\n");
		assert.match({ reused: 0, walked: 2 }, edit('{string} n', '{int} n'));
		assert.match(null, differs());
	});

	it('builds afresh once the imports changed', () => {
		open(FIVE);
		documents.markStale(URI);
		documents.get(URI);
		assert.match({ reused: 0, walked: 5 }, lastBuildStats());
	});

	it('builds afresh when reusing the previous map throws', () => {
		open(FIVE);
		for (let u in documents.peek(URI).built.units) u.root = null;
		assert.match({ reused: 0, walked: 5 }, edit('[ 1, 2 ]', '[ 1, 3 ]'));
		assert.match(null, differs());
	});

	it('uses a map built from scratch when asked to check a reused one, and it differs', () => {
		open(FIVE);
		corruptY();
		edit('[ 1, 2 ]', '[ 1, 3 ]');
		assert.match(true, differs() !== null);

		documents.close(URI);
		documents.checkIncremental(true);
		open(FIVE);
		corruptY();
		assert.match({ reused: 4, walked: 1 }, edit('[ 1, 2 ]', '[ 1, 3 ]'));
		assert.match(null, differs());
		// Nor is the next built from it.
		assert.match({ reused: 0, walked: 5 }, edit('[ 1, 3 ]', '[ 1, 4 ]'));
	});

	it('matches a map built from scratch after random edits', () => {
		let seed = 20261018;
		let rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
		const TOKENS = [ 'x', ' ', ';', '1', '\n', '(', ')', '{', '}', "'", 'null', ' = 1', 'return x;',
			'// c', 'let q = 1;', 'x = null;', '.y', '?', ',', 'function g() {}', '++' ];
		for (let round = 0; round < 4; round++) {
			let text = fixture.read('incremental.uc');
			open(text);
			for (let k = 0; k < 15; k++) {
				let at = rnd(length(text) + 1);
				text = (rnd(3) > 0)
					? substr(text, 0, at) + TOKENS[rnd(length(TOKENS))] + substr(text, at)
					: substr(text, 0, at) + substr(text, at + 1 + rnd(3));
				dag.update(URI, text, documents.change(URI, [ { text } ], _version++).tree, documents.all());
				let d = differs();
				assert.match(null, d, sprintf('round %d, edit %d', round, k));
				if (d) break;
			}
		}
	});
});
