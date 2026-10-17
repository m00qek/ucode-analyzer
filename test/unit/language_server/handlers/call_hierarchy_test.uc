import { describe, it, assert, afterEach, mock, any_order } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { SymbolKind } from 'ucode_analyzer.code_analysis.lsp_types';
import { prepareCallHierarchy, incomingCalls, outgoingCalls } from 'ucode_analyzer.language_server.handlers.call_hierarchy';
import { cursors, locate } from 'cursor';
import * as fixture from 'fixture';

dag.init(fixture.config());

let URI       = 'file:///ch.uc';
let GREET     = fixture.uri('greet.uc');
let SETTINGS  = fixture.uri('settings.uc');
let DEEP      = fixture.uri('reexport/deep.uc');
let WRAPPER   = fixture.uri('reexport/wrapper.uc');
let ZERO      = { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } };

let opened = [];

// Open text at uri, also indexed so its imports resolve (the fixtures they
// import are indexed from disk).
function openAt(uri, text) {
	documents.open(uri, text, 1);
	dag.add(uri, text, documents.get(uri).tree);
	push(opened, uri);
	return documents.get(uri);
}

function fromDisk(uri) {
	dag.addFromDisk(uri);
	push(opened, uri);
}

afterEach(() => {
	for (let uri in opened) {
		documents.close(uri);
		dag.remove(uri);
	}
	opened = [];
});

function prepareAt(src, uri) {
	uri ??= URI;
	return prepareCallHierarchy(uri, openAt(uri, src.text), src.at[0]);
}

function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

// The range of the nth (default 0) occurrence of needle, on one line.
function rangeIn(text, needle, nth) {
	let start = locate(text, needle, nth);
	return { start, end: { line: start.line, character: start.character + length(needle) } };
}

// A function's CallHierarchyItem; nameByteOffset is where its name starts.
function fnItem(name, uri, range, selectionRange, nameByteOffset) {
	return { name, kind: SymbolKind.FUNCTION, uri, range, selectionRange, data: { uri, nameByteOffset } };
}

// The item of a file's module-level code.
function moduleItem(uri, name) {
	return { name, kind: SymbolKind.MODULE, uri, range: ZERO, selectionRange: ZERO,
		data: { uri, nameByteOffset: -1 } };
}

// greet.uc's `function greet() {}`, as an item.
function greetItem() {
	let text = fixture.read('greet.uc');
	return fnItem('greet', GREET, { start: locate(text, 'function'), end: locate(text, '{}', 0, 2) },
		rangeIn(text, 'greet'), index(text, 'greet'));
}

describe('prepareCallHierarchy — local functions', () => {
	it('on a function declaration name: the whole declaration, selecting the name', () => {
		let src = cursors("$1function $0$2greet$3(name) { return name; }$4\ngreet('x');\n");
		assert.match([ fnItem('greet', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]) ], prepareAt(src));
	});

	it('on an exported function declaration: the declaration without `export`', () => {
		let src = cursors("export $1function $0$2f$3() {}$4;\n");
		assert.match([ fnItem('f', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]) ], prepareAt(src));
	});

	it('on a variable holding a function or an arrow: the whole declaration', () => {
		for (let marked in [ "$1let $0$2f$3 = function() { return 1; };$4\n", "$1const $0$2f$3 = (a) => a;$4\n" ]) {
			let src = cursors(marked);
			assert.match([ fnItem('f', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]) ], prepareAt(src), marked);
		}
	});

	it('on a call: the called function', () => {
		let src = cursors("$1function $2foo$3() {}$4\nfunction bar() { f$0oo(); }\n");
		assert.match([ fnItem('foo', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]) ], prepareAt(src));
	});

	it('on a call of a variable holding an arrow: its declaration', () => {
		let src = cursors("$1let $2f$3 = () => 1;$4\n$0f();\n");
		assert.match([ fnItem('f', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]) ], prepareAt(src));
	});

	it('returns null on what is not a function', () => {
		for (let marked in [
			"let $0x = 1;\n",                         // a variable holding a value
			"let x = 1;\n$0x;\n",                     // its use
			"function f($0a) { return a; }\n",        // a parameter
			"function f(a) { return $0a; }\n",        // its use
			"$0function f() {}\n",                    // a keyword
			"$0print(1);\n",                          // an undeclared name
			// A call above the declaration is not its use: no hoisting.
			"$0foo();\nfunction foo() {}\n",
		])
			assert.match(null, prepareAt(cursors(marked)), marked);
	});

	it('returns null past the end of the text', () => {
		documents.open(URI, "function f() {}\n", 1);
		push(opened, URI);
		assert.match(null, prepareCallHierarchy(URI, documents.get(URI), { line: 9, character: 0 }));
	});
});

describe('prepareCallHierarchy — imported functions', () => {
	it('on a call of an imported function, or its import: the item in the declaring file', () => {
		fromDisk(GREET);
		let src = cursors("import { $1greet } from 'greet';\n$0greet();\n");
		let user = fixture.uri('ch_user.uc');
		assert.match([ greetItem() ], prepareAt(src, user));
		assert.match([ greetItem() ], prepareCallHierarchy(user, documents.get(user), src.at[1]));
	});

	it('follows a re-export to the module that declares the function', () => {
		fromDisk(DEEP);
		fromDisk(WRAPPER);
		let src = cursors("import { thing } from 'reexport.wrapper';\n$0thing();\n");
		let text = fixture.read('reexport/deep.uc');
		assert.match([ fnItem('thing', DEEP, { start: locate(text, 'function'), end: locate(text, '}', 0, 1) },
			rangeIn(text, 'thing', 1), index(text, 'function thing') + 9) ], prepareAt(src, fixture.uri('ch_user.uc')));
	});

	it('on an imported arrow: the arrow alone, unlike a local one', () => {
		fromDisk(SETTINGS);
		let src = cursors("import { pick } from 'settings';\n$0pick([]);\n");
		let text = fixture.read('settings.uc');
		let arrow = '(list, ...rest) => list[0]';
		assert.match([ fnItem('pick', SETTINGS, rangeIn(text, arrow), rangeIn(text, 'pick'), index(text, 'pick')) ],
			prepareAt(src, fixture.uri('ch_user.uc')));
	});

	it('returns null on an imported value that is not a function', () => {
		fromDisk(SETTINGS);
		assert.match(null, prepareAt(cursors("import { VERSION } from 'settings';\n$0VERSION;\n"), fixture.uri('ch_user.uc')));
	});

	it('returns null on an aliased import', () => {
		// Suspected bug: hi() calls greet, and outgoingCalls() resolves the alias,
		// but resolveExportIdentity keeps an alias local (as rename needs).
		fromDisk(GREET);
		assert.match(null, prepareAt(cursors("import { greet as hi } from 'greet';\n$0hi();\n"), fixture.uri('ch_user.uc')));
	});
});

describe('incomingCalls — within a file', () => {
	it('groups the call sites by the calling function', () => {
		let src = cursors("function $0foo() {}\n$1function $2bar$3() { $5foo$6(); $7foo$8(); }$4\n");
		let item = prepareAt(src)[0];
		assert.match([ { from: fnItem('bar', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]),
			fromRanges: any_order([ span(src, 5, 6), span(src, 7, 8) ]) } ], incomingCalls(item));
	});

	it('gives calls outside any function to the module item', () => {
		let src = cursors("function $0foo() {}\n$1foo$2();\nlet x = $3foo$4();\n");
		assert.match([ { from: moduleItem(URI, 'ch.uc'), fromRanges: any_order([ span(src, 1, 2), span(src, 3, 4) ]) } ],
			incomingCalls(prepareAt(src)[0]));
	});

	it('names a caller held in a variable after it', () => {
		let src = cursors("function $0foo() {}\n$1let $2baz$3 = () => $5foo$6();$4\n");
		assert.match([ { from: fnItem('baz', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]),
			fromRanges: [ span(src, 5, 6) ] } ], incomingCalls(prepareAt(src)[0]));
	});

	it('calls an anonymous caller (anonymous), selecting all of it', () => {
		let src = cursors("function $0foo() {}\nmap([], $1function() { $3foo$4(); }$2);\nmap([], $5() => $7foo$8()$6);\n");
		assert.match(any_order([
			{ from: fnItem('(anonymous)', URI, span(src, 1, 2), span(src, 1, 2), src.offset[1]), fromRanges: [ span(src, 3, 4) ] },
			{ from: fnItem('(anonymous)', URI, span(src, 5, 6), span(src, 5, 6), src.offset[5]), fromRanges: [ span(src, 7, 8) ] },
		]), incomingCalls(prepareAt(src)[0]));
	});

	it('gives a call in a nested function to the innermost one', () => {
		let src = cursors("function $0foo() {}\nfunction outer() {\n\t$1function $2inner$3() { $5foo$6(); }$4\n}\n");
		assert.match([ { from: fnItem('inner', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]),
			fromRanges: [ span(src, 5, 6) ] } ], incomingCalls(prepareAt(src)[0]));
	});

	it('lists a recursive function as its own caller', () => {
		let src = cursors("$1function $0$2foo$3() { $5foo$6(); }$4\n");
		assert.match([ { from: fnItem('foo', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]),
			fromRanges: [ span(src, 5, 6) ] } ], incomingCalls(prepareAt(src)[0]));
	});

	it('returns null without calls: a reference, an argument, a member, a shadowing name', () => {
		let src = cursors("function $0foo() {}\nlet g = foo;\nmap([], foo);\nfoo.x;\nfunction bar(foo) { foo(); }\n");
		assert.match(null, incomingCalls(prepareAt(src)[0]));
	});

	it('returns null for a file that is neither open nor on disk', () => {
		assert.match(null, incomingCalls(fnItem('f', 'file:///nowhere.uc', ZERO, ZERO, 0)));
	});
});

describe('incomingCalls — across files', () => {
	it('finds the callers in importers, by named and aliased import', () => {
		fromDisk(GREET);
		let named = cursors("import { greet } from 'greet';\n$1function $2run$3() { $5greet$6(); }$4\n$7greet$8(); greet;\n");
		let aliased = cursors("import { greet as hi } from 'greet';\n$1hi$2(); $3hi$4();\n");
		let NAMED = fixture.uri('ch_named.uc'), ALIASED = fixture.uri('ch_aliased.uc');
		openAt(NAMED, named.text);
		openAt(ALIASED, aliased.text);

		assert.match(any_order([
			{ from: fnItem('run', NAMED, span(named, 1, 4), span(named, 2, 3), named.offset[2]), fromRanges: [ span(named, 5, 6) ] },
			{ from: moduleItem(NAMED, 'ch_named.uc'), fromRanges: [ span(named, 7, 8) ] },
			{ from: moduleItem(ALIASED, 'ch_aliased.uc'), fromRanges: any_order([ span(aliased, 1, 2), span(aliased, 3, 4) ]) },
		]), incomingCalls(greetItem()));
	});

	it('finds the callers in the declaring file and in its importers', () => {
		let lib = cursors("export function $0foo() {}\n$1function $2bar$3() { $5foo$6(); }$4\n");
		let user = cursors("import { foo } from 'ch_lib';\n$1foo$2();\n");
		let LIB = fixture.uri('ch_lib.uc'), USER = fixture.uri('ch_lib_user.uc');
		// ch_lib is not on disk: let the import resolve to it.
		mock.global.patch('fs', { data: { [fixture.WORKSPACE + '/ch_lib.uc']: lib.text } });
		openAt(LIB, lib.text);
		openAt(USER, user.text);
		mock.global.unpatch('fs');

		let item = prepareCallHierarchy(LIB, documents.get(LIB), lib.at[0])[0];
		assert.match(any_order([
			{ from: fnItem('bar', LIB, span(lib, 1, 4), span(lib, 2, 3), lib.offset[2]), fromRanges: [ span(lib, 5, 6) ] },
			{ from: moduleItem(USER, 'ch_lib_user.uc'), fromRanges: [ span(user, 1, 2) ] },
		]), incomingCalls(item));
	});

	// BUG: asserts the correct behaviour and fails today. A namespace call's
	// reference is the property `greet` of `g.greet`, whose parent is the
	// member expression, so isCallSite() rejects it.
	it('finds a call through a namespace import', () => {
		fromDisk(GREET);
		let src = cursors("import * as g from 'greet';\ng.$1greet$2();\n");
		let NS = fixture.uri('ch_ns.uc');
		openAt(NS, src.text);
		assert.match([ { from: moduleItem(NS, 'ch_ns.uc'), fromRanges: [ span(src, 1, 2) ] } ], incomingCalls(greetItem()));
	});
});

describe('outgoingCalls', () => {
	it('lists each called function once, with all its call sites', () => {
		let src = cursors("$1function $2foo$3() {}$4\nlet $5bar$6 = $7() => 1$8;\nfunction $0run() { foo(); bar(); foo(); }\n");
		let calls = outgoingCalls(prepareAt(src)[0]);
		let text = src.text;
		assert.match(any_order([
			{ to: fnItem('foo', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]),
			  fromRanges: any_order([ rangeIn(text, 'foo', 1), rangeIn(text, 'foo', 2) ]) },
			// The callee item of a variable spans the arrow alone, unlike prepare's.
			{ to: fnItem('bar', URI, span(src, 7, 8), span(src, 5, 6), src.offset[5]),
			  fromRanges: [ rangeIn(text, 'bar', 1) ] },
		]), calls);
	});

	it('follows calls into arguments but not into nested functions', () => {
		let text = "function foo() {}\nfunction bar() {}\nfunction baz() {}\n" +
			"function run() { foo(bar()); let f = function() { baz(); }; map([], () => baz()); }\n";
		let calls = outgoingCalls(prepareCallHierarchy(URI, openAt(URI, text), locate(text, 'run'))[0]);
		assert.match(any_order([ 'foo', 'bar' ]), map(calls, (c) => c.to.name));
	});

	it('resolves a call of a local exported function', () => {
		let src = cursors("export $1function $2foo$3() {}$4;\nfunction $0run() { $5foo$6(); }\n");
		assert.match([ { to: fnItem('foo', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]), fromRanges: [ span(src, 5, 6) ] } ],
			outgoingCalls(prepareAt(src)[0]));
	});

	it('resolves an imported function, also under an alias', () => {
		fromDisk(GREET);
		for (let marked in [
			"import { greet } from 'greet';\nfunction $0run() { $1greet$2(); }\n",
			"import { greet as hi } from 'greet';\nfunction $0run() { $1hi$2(); }\n",
		]) {
			let src = cursors(marked);
			assert.match([ { to: greetItem(), fromRanges: [ span(src, 1, 2) ] } ],
				outgoingCalls(prepareAt(src, fixture.uri('ch_user.uc'))[0]), marked);
		}
	});

	it('lists the call that is the body of an arrow', () => {
		let src = cursors("$1function $2foo$3() {}$4\nlet $0f = () => $5foo$6();\n");
		assert.match([ { to: fnItem('foo', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]), fromRanges: [ span(src, 5, 6) ] } ],
			outgoingCalls(prepareAt(src)[0]));
	});

	it('returns null without resolvable calls: none, a method, an undeclared function', () => {
		for (let marked in [ "function $0run() { return 1; }\n", "let o = {};\nfunction $0run() { o.m(); print(1); }\n" ])
			assert.match(null, outgoingCalls(prepareAt(cursors(marked))[0]), marked);
	});

	it('returns null for the module item or a file that is neither open nor on disk', () => {
		openAt(URI, "foo();\nfunction foo() {}\n");
		assert.match(null, outgoingCalls(moduleItem(URI, 'ch.uc')));
		assert.match(null, outgoingCalls(fnItem('f', 'file:///nowhere.uc', ZERO, ZERO, 0)));
	});

	// BUG: these assert the correct behaviour and fail today: callees are
	// looked up by name among the imports and the top-level declarations,
	// ignoring scope.

	it('resolves a call of a nested function', () => {
		let src = cursors("function $0run() {\n\t$1function $2inner$3() {}$4\n\t$5inner$6();\n}\n");
		assert.match([ { to: fnItem('inner', URI, span(src, 1, 4), span(src, 2, 3), src.offset[2]), fromRanges: [ span(src, 5, 6) ] } ],
			outgoingCalls(prepareAt(src)[0]));
	});

	it('does not resolve a parameter to the top-level function it shadows', () => {
		let src = cursors("function foo() {}\nfunction $0run(foo) { foo(); }\n");
		assert.match(null, outgoingCalls(prepareAt(src)[0]));
	});
});
