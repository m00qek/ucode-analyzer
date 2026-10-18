// Edit sequences after noah-lsp's incremental soundness suite (MIT,
// github.com/NoahBPeterson/ucode-lsp, tests/incremental): at every step, the
// scope map reusing the last one must match one built from scratch.

import { describe, it, assert, afterEach } from 'utest';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { buildScopeMap, lastBuildStats } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { mapDifference } from 'ucode_analyzer.code_analysis.types.type_eq';
import { typeErrors } from 'ucode_analyzer.code_analysis.diagnostics.type_errors';
import * as fixture from 'fixture';

dag.init(fixture.config());
let _globalUri = dag.resolveSpecifier('global');
if (_globalUri) {
	dag.addFromDisk(_globalUri);
	initBuiltinsFromDag(_globalUri);
}

let URI = fixture.uri('test_incremental_cases.uc');
let _version = 1;

afterEach(() => documents.close(URI));

function differs() {
	let doc = documents.get(URI);
	let full = buildScopeMap(URI, doc.text, doc.tree);
	let d = mapDifference(doc.scopeMap, full);
	if (d) return d;
	let e1 = sprintf('%J', typeErrors(URI, doc)), e2 = sprintf('%J', typeErrors(URI, { ...doc, scopeMap: full }));
	return (e1 === e2) ? null : sprintf('diagnostics %s vs %s', e1, e2);
}

// Open the first text and edit it into each next; the functions reused in all.
function run(texts) {
	let reused = 0;
	for (let i = 0; i < length(texts); i++) {
		if (i === 0) documents.open(URI, texts[0], _version++);
		else dag.update(URI, texts[i], documents.change(URI, [ { text: texts[i] } ], _version++).tree, documents.all());
		assert.match(null, differs(), sprintf('text %d', i));
		reused += lastBuildStats().reused;
	}
	return reused;
}

// Each takes the inside of one function body and puts it among siblings.
let topFn = (b) => `function helper(x) {\n${b}\n}\nfunction other(y) {\n\treturn y + 1;\n}\nlet r = helper(1) + other(2);\n`;
let objMethod = (b) => `let o = {\n\thelper: function(x) {\n${b}\n\t},\n\tother: function(y) { return y * 2; }\n};\nlet r = o.helper(1);\n`;
let arrowLet = (b) => `let helper = (x) => {\n${b}\n};\nlet other = (y) => y + 1;\nlet r = helper(1) + other(2);\n`;
let fnExprConst = (b) => `const helper = function(x) {\n${b}\n};\nconst other = function(y) { return y - 1; };\nlet r = helper(1) + other(2);\n`;
let returnShape = (b) => `function build() {\n\treturn {\n\t\thelper: function(x) {\n${b}\n\t\t},\n\t\tother: function(y) { return y; }\n\t};\n}\nlet api = build();\n`;
let nestedObj = (b) => `let cfg = {\n\tinner: {\n\t\thelper: function(x) {\n${b}\n\t\t}\n\t},\n\tother: function(y) { return y; }\n};\nlet r = cfg.inner.helper(1);\n`;
let twoFns = (h, o) => `function helper(x) {\n${h}\n}\nfunction other(y) {\n${o}\n}\nlet r = helper(1)+other(2);\n`;
let setGet = (s, g) => `let o = {\n\tset: function(v) {\n${s}\n\t},\n\tget: function() {\n${g}\n\t}\n};\nlet r = o.get();\n`;
let fw = (b1, b2) => `let fw = {\n\tparse_invert: function(val) { return { val: val, invert: false }; },\n\thelper: function(x) {\n${b1}\n\t},\n\tother: function(y) {\n${b2}\n\t}\n};\n`;

// Three texts: f(a), f(b), f(a).
function back(f, a, b) {
	return [ f(a), f(b), f(a) ];
}

// [ name, texts, whether a function is reused ]
const CASES = [
	[ 'top-level function: whitespace, then a comment', [ topFn('\treturn x + 1;'), topFn('\treturn x + 1;  '), topFn('\treturn x + 1; // note') ], true ],
	[ 'object method: a comment, then none', [ objMethod('\t\treturn x + 1;'), objMethod('\t\treturn x + 1; // c'), objMethod('\t\treturn x + 1;') ], true ],
	[ 'arrow function in a let: comments', [ arrowLet('\treturn x + 1;'), arrowLet('\treturn x + 1; // a'), arrowLet('\treturn x + 1; // b') ] ],
	[ 'function expression in a const: whitespace', [ fnExprConst('\treturn x + 1;'), fnExprConst('\treturn x + 1;   '), fnExprConst('\treturn x + 1;') ] ],
	[ 'method of an object a function returns: a comment', back(returnShape, '\t\t\treturn x + 1;', '\t\t\treturn x + 1; // m') ],
	[ 'method of a nested object: a comment', back(nestedObj, '\t\t\treturn x + 1;', '\t\t\treturn x + 1; // n') ],
	[ 'blank line added in a body', [ topFn('\tlet a = x;\n\treturn a;'), topFn('\tlet a = x;\n\n\treturn a;') ] ],
	[ 'trailing whitespace, many times', map([ '', ' ', '  ', '', ' ' ], (s) => objMethod('\t\treturn x;' + s)), true ],
	[ 'comment-only changes', map([ 'first', 'second', 'third' ], (s) => topFn(`\t// ${s}\n\treturn x;`)), true ],
	[ 'a block comment grows', map([ 'a', 'a b', 'a b c' ], (s) => topFn(`\t/* ${s} */\n\treturn x;`)), true ],

	[ 'local renamed', [ topFn('\tlet a = x + 1;\n\treturn a;'), topFn('\tlet b = x + 1;\n\treturn b;') ] ],
	[ 'statement added', [ topFn('\treturn x;'), topFn('\tlet t = x + 2;\n\treturn t;') ] ],
	[ 'statement removed', [ topFn('\tlet t = x + 2;\n\treturn t;'), topFn('\treturn x;') ] ],
	[ 'statements reordered', [ topFn('\tlet a = 1;\n\tlet b = 2;\n\treturn a + b;'), topFn('\tlet b = 2;\n\tlet a = 1;\n\treturn a + b;') ] ],
	[ 'operator changed', [ objMethod('\t\treturn x + 1;'), objMethod('\t\treturn x - 1;'), objMethod('\t\treturn x * 1;') ], true ],
	[ 'loop added', [ topFn('\treturn x;'), topFn('\tlet s = 0;\n\tfor (let i = 0; i < x; i++) s += i;\n\treturn s;') ] ],
	[ 'inner function added', [ topFn('\treturn x;'), topFn('\tfunction inner(z) { return z + 1; }\n\treturn inner(x);') ] ],
	[ 'string literal changed in a method', [ objMethod('\t\treturn "a" + x;'), objMethod('\t\treturn "b" + x;') ], true ],
	[ 'conditional added', [ topFn('\treturn x;'), topFn('\tif (x > 0) return x;\n\treturn 0;') ] ],
	[ 'if and else swapped', [ topFn('\tif (x > 0) return 1;\n\treturn 2;'), topFn('\tif (x <= 0) return 2;\n\treturn 1;') ], true ],

	[ 'undefined variable, then fixed', back(topFn, '\treturn x;', '\treturn nope;') ],
	[ 'syntax error, then fixed', back(objMethod, '\t\treturn x;', '\t\treturn x.;') ],
	[ 'two undefined variables in turn', [ topFn('\treturn x;'), topFn('\treturn aaa;'), topFn('\treturn bbb;'), topFn('\treturn x;') ] ],
	[ 'error in one function while another is edited', [ twoFns('\treturn nope;', '\treturn y;'), twoFns('\treturn nope;', '\treturn y + 1;') ], true ],
	[ 'undefined variable in a method, then fixed', back(objMethod, '\t\treturn x;', '\t\treturn missing;') ],
	[ 'undefined function called, then fixed', back(topFn, '\treturn x;', '\treturn nope_fn(x);') ],
	[ 'error in an arrow function, then fixed', back(arrowLet, '\treturn x;', '\treturn zzz;') ],
	[ 'several errors in one body, then fixed', back(topFn, '\treturn x;', '\tlet a = p;\n\treturn q;') ],

	[ 'parameter added', [ topFn('\treturn x;'), 'function helper(x, z) {\n\treturn x + z;\n}\nfunction other(y){return y;}\nlet r=helper(1,2)+other(3);\n', topFn('\treturn x;') ] ],
	[ 'parameter removed from a method', [ 'let o={ helper:function(x,z){ return x+z; }, other:function(y){return y;} };\nlet r=o.helper(1,2);\n',
		'let o={ helper:function(x){ return x; }, other:function(y){return y;} };\nlet r=o.helper(1);\n' ] ],
	[ 'function renamed', [ topFn('\treturn x;'), 'function renamed(x){ return x; }\nfunction other(y){return y;}\nlet r=renamed(1)+other(2);\n' ] ],
	[ 'arrow parameter renamed', [ arrowLet('\treturn x;'), 'let helper=(q)=>{ return q; };\nlet other=(y)=>y;\nlet r=helper(1)+other(2);\n' ] ],
	[ 'let to const', [ fnExprConst('\treturn x;'), 'let helper=function(x){ return x; };\nconst other=function(y){return y;};\nlet r=helper(1)+other(2);\n' ] ],
	[ 'rest parameter added', [ topFn('\treturn x;'), 'function helper(x, ...rest){ return x; }\nfunction other(y){return y;}\nlet r=helper(1)+other(2);\n' ] ],
	[ 'function expression to arrow', [ 'let o={ helper:function(x){ return x; }, other:function(y){return y;} };\nlet r=o.helper(1);\n',
		'let o={ helper:(x)=>{ return x; }, other:function(y){return y;} };\nlet r=o.helper(1);\n' ] ],
	[ "'use strict' added", [ topFn('\treturn x;'), "'use strict';\n" + topFn('\treturn x;') ] ],

	[ 'function added', [ topFn('\treturn x;'), topFn('\treturn x;') + 'function extra(z){ return z+1; }\n' ], true ],
	[ 'function removed', [ topFn('\treturn x;') + 'function extra(z){ return z+1; }\n', topFn('\treturn x;') ], true ],
	[ 'method added', [ 'let o={ helper:function(x){return x;} };\nlet r=o.helper(1);\n',
		'let o={ helper:function(x){return x;}, extra:function(z){return z+1;} };\nlet r=o.helper(1);\n' ] ],
	[ 'method removed', [ 'let o={ helper:function(x){return x;}, extra:function(z){return z+1;} };\nlet r=o.helper(1);\n',
		'let o={ helper:function(x){return x;} };\nlet r=o.helper(1);\n' ] ],
	[ 'methods reordered', [ 'let o={ a:function(x){return x;}, b:function(y){return y;} };\nlet r=o.a(1)+o.b(2);\n',
		'let o={ b:function(y){return y;}, a:function(x){return x;} };\nlet r=o.a(1)+o.b(2);\n' ] ],
	[ 'functions reordered', [ 'function a(x){return x;}\nfunction b(y){return y;}\nlet r=a(1)+b(2);\n',
		'function b(y){return y;}\nfunction a(x){return x;}\nlet r=a(1)+b(2);\n' ] ],
	[ 'statement added between functions', [ 'function a(x){return x;}\nfunction b(y){return y;}\n',
		'function a(x){return x;}\nlet mid = 7;\nfunction b(y){return y;}\n' ] ],
	[ 'two functions wrapped in an object', [ 'function a(x){return x;}\nfunction b(y){return y;}\nlet r=a(1)+b(2);\n',
		'let o={ a:function(x){return x;}, b:function(y){return y;} };\nlet r=o.a(1)+o.b(2);\n' ] ],

	[ 'setter writing this: a comment', [ setGet('\t\tthis.val = v;\n\t\treturn v;', '\t\treturn this.val;'), setGet('\t\tthis.val = v; // c\n\t\treturn v;', '\t\treturn this.val;') ], true ],
	[ 'getter edited, setter not', [ setGet('\t\tthis.val = v;\n\t\treturn v;', '\t\treturn this.val;'), setGet('\t\tthis.val = v;\n\t\treturn v;', '\t\treturn this.val; // g') ], true ],
	[ 'this property: int to object', back((r) => `let o={ set:function(){ this.val=${r}; return 1; }, get:function(){ return this.val.x; } };\nlet r=o.get();`, '5', '{ x: 9 }') ],
	[ 'this property: string to array', back((r) => `let o={ set:function(){ this.val=${r}; return 1; }, get:function(){ return this.val; } };\nlet r=o.get();`, '"hi"', '[1,2,3]') ],
	[ 'one of two this properties edited', map([ [ '1', '2' ], [ '1', '99' ], [ '7', '2' ] ], (p) =>
		`let o={ init:function(){ this.a=${p[0]}; this.b=${p[1]}; }, read:function(){ return this.a; } };\nlet r=o.read();`) ],
	[ 'this property written under a condition', map([ '5', '"s"' ], (r) => `let o={ set:function(f){ if(f) this.val=${r}; return 1; }, get:function(){ return this.val; } };\nlet r=o.get();`) ],
	[ 'a sibling reads a member of a this property', back((r) => `let o={ build:function(){ this.cfg=${r}; }, host:function(){ return this.cfg.host; } };\nlet r=o.host();`, '{ host: "a" }', '{ port: 1 }') ],
	[ 'this written: comments, many times', map([ '', ' // 1', ' // 2' ], (c) => setGet(`\t\tthis.val = v;${c}\n\t\treturn v;`, '\t\treturn this.val;')), true ],
	[ 'this write added', [ 'let o={ set:function(v){ return v; }, get:function(){ return this.val; } };\nlet r=o.get();',
		'let o={ set:function(v){ this.val=v; return v; }, get:function(){ return this.val; } };\nlet r=o.get();' ] ],
	[ 'this write removed', [ 'let o={ set:function(v){ this.val=v; return v; }, get:function(){ return this.val; } };\nlet r=o.get();',
		'let o={ set:function(v){ return v; }, get:function(){ return this.val; } };\nlet r=o.get();' ] ],

	[ 'global property written in a method', back((r) => `let o={ set:function(){ global.G=${r}; return 1; }, get:function(){ return global.G; } };\nlet r=o.get();`, '5', '"s"') ],
	[ 'global property written in a function', back((r) => `function setit(){ global.COUNT=${r}; }\nfunction other(y){return y;}\nsetit();\n`, '0', '1') ],
	[ 'hex literal written to a global property', back((r) => `function setit(){ global.MASK=${r}; return global.MASK; }\nlet r=setit();\n`, '0xF', '0xFF') ],
	[ 'a function writing globals edited beside another', back((d) => `function keep(x){ return x + 1; }\nfunction dirty(){\n${d}\n}\nlet r=keep(1);\ndirty();\n`,
		'\tglobal.Z=1;\n\treturn global.Z;', '\tglobal.Z=1; // c\n\treturn global.Z;'), true ],
	[ 'module variable assigned in a function', back((r) => `let acc = 0;\nfunction add(){ acc = ${r}; return acc; }\nlet r = add();\n`, '1', '2') ],
	[ 'module object member assigned in a function', back((r) => `let store = {};\nfunction put(){ store.k = ${r}; return store.k; }\nlet r = put();\n`, '5', '"x"') ],

	[ 'method return type changed, method caller', back((r) => `let o={ make:function(){ return ${r}; }, use:function(){ let v=this.make(); return v.y; } };\nlet r=o.use();`, '7', '{ y: 1 }') ],
	[ 'function return type changed, method caller', back((r) => `function make(){ return ${r}; }\nlet o={ use:function(){ let v=make(); return v.z; } };\nlet r=o.use();`, '3', '{ z: 1 }') ],
	[ 'property added to a returned object', back((p) => `function make(){ return { ${p} }; }\nfunction use(){ let v=make(); return v.b; }\nlet r=use();`, 'a: 1', 'a: 1, b: 2') ],
	[ 'property removed from a returned object', back((p) => `function make(){ return { ${p} }; }\nfunction use(){ let v=make(); return v.b.c; }\nlet r=use();`, 'b: { c: 1 }', 'b: 2') ],
	[ 'arrow function return type changed', back((r) => `let make=()=>${r};\nfunction use(){ let v=make(); return v.k; }\nlet r=use();`, '5', '({ k: 1 })') ],
	[ 'method of a returned object: return type changed', back((r) => `function build(){ return { val:function(){ return ${r}; } }; }\nlet api=build();\nlet r=api.val();\n`, '1', '{ n: 1 }') ],
	[ 'this property type changed, read by two methods', back((r) => `let o={ init:function(){ this.data=${r}; }, a:function(){ return this.data.x; }, b:function(){ return this.data; } };\nlet r=o.a();`, '{ x: 1 }', '5') ],
	[ 'return type changed through a chain of calls', back((r) => `function a(){ return ${r}; }\nfunction b(){ let v=a(); return v.m; }\nfunction c(){ return b(); }\nlet r=c();`, '{ m: 1 }', '9') ],
	[ 'return type int to string, used in arithmetic', back((r) => `function n(){ return ${r}; }\nfunction use(){ let v=n(); return v * 2; }\nlet r=use();`, '5', '"x"') ],
	[ 'return type may be null', back((r) => `function maybe(){ ${r} }\nfunction use(){ let v=maybe(); return index(v, 1); }\nlet r=use();`, 'return [1,2];', 'if (1) return [1,2]; return null;') ],
	[ 'a called function gets an error', back((b) => `function dep(){ ${b} }\nfunction use(){ return dep(); }\nlet r=use();`, 'return 1;', 'return undefined_thing;') ],
	[ 'two readers of a changed return type', back((r) => `function p(){ return ${r}; }\nfunction r1(){ let v=p(); return v.a; }\nfunction r2(){ let v=p(); return v.b; }\nlet r=r1()+r2();`, '{ a: 1, b: 2 }', '{ a: 1 }') ],
	[ 'returned value edited: its literal type changes', map([ '1', '2', '3' ], (n) => `function p(){ return { a: ${n} }; }\nfunction use(){ let v=p(); return v.a; }\nlet r=use();`) ],

	[ 'middle of three objects edited, many times', map([ '', ' // 1', ' + 1', ' // 2' ], (s) =>
		`let A={ f:function(x){return x;} };\nlet B={ g:function(y){\n\t\treturn y;${s}\n} };\nlet C={ h:function(z){return z;} };\nlet r=A.f(1)+B.g(2)+C.h(3);\n`), true ],
	[ 'whitespace churn over one body', map([ 0, 1, 2, 3, 4, 5, 6, 7 ], (i) => topFn('\treturn x;' + substr('        ', 0, i))), true ],
	[ 'two bodies in turn', map([ 0, 1, 2, 3, 4, 5 ], (i) => objMethod((i % 2) ? '\t\treturn x + 1;' : '\t\treturn x - 1;')), true ],
	[ 'immediately called function', map([ '\treturn 1;', '\treturn 1; // c', '\treturn 2;' ], (b) => `let r = (function(){\n${b}\n})();\nfunction other(y){return y;}\n`) ],
	[ 'recursive function', map([ '', ' // base' ], (c) => `function fac(n){\n\tif (n <= 1) return 1;${c}\n\treturn n * fac(n-1);\n}\nlet r=fac(5);\n`) ],
	[ 'empty body, then not, then empty', [ topFn(''), topFn('\treturn x;'), topFn('') ] ],
	[ 'method switched between arrow and function expression', map([ 0, 1, 2, 3 ], (i) => (i % 2)
		? 'let o={ m:(x)=>{return x;}, other:function(y){return y;} };\nlet r=o.m(1);\n'
		: 'let o={ m:function(x){return x;}, other:function(y){return y;} };\nlet r=o.m(1);\n') ],
	[ 'no functions', [ 'let a = 1;\nlet b = a + 1;\nprint(b);\n', 'let a = 1;\nlet b = a + 2;\nprint(b);\n' ] ],
	[ 'a sibling increments a module variable', back((b) => `let g = 0;\nfunction bump() {\n\tg++;\n}\nfunction read(x) {\n${b}\n}\nbump();\nlet r = read(1);\n`, '\treturn x;', '\treturn x + 1; // edited') ],

	[ 'methods of one object: comment, then the other body', [ fw('\t\tlet a = x + 1; return a;', '\t\treturn y * 2;'),
		fw('\t\tlet a = x + 1;  return a; // tweak', '\t\treturn y * 2;'), fw('\t\tlet a = x + 1;  return a;', '\t\treturn y * 2; // c') ], true ],
	[ 'methods of one object: syntax error, then fixed', back((b) => fw(b, '\t\treturn y;'), '\t\treturn x;', '\t\treturn x.;') ],
	[ 'methods of one object: undefined variable, other body edited', [ fw('\t\treturn nope;', '\t\treturn y;'), fw('\t\treturn nope;', '\t\treturn y + 1;') ] ],
	[ 'module returning an object: a method edited', map([ 'return r;', 'return r; // tweak' ], (r) =>
		`'use strict';\nfunction helper(x) { return x + 1; }\nreturn {\n  api: function(a) { let r = helper(a); ${r} },\n  other: function(b) { return b * 2; }\n};\n`), true ],
	[ 'functions, a this write and a module variable', map([ [ '(x)', '' ], [ '(x)', ' // c' ], [ '(x, y)', '' ] ], (p) =>
		`let o = {\n  init: function() { this.val = 5; return 1; },\n  read: function() { return this.val; }\n};\nfunction pure${p[0]} { return x + 1;${p[1]} }\nlet acc = 0;\nfunction impure() { acc = acc + 1; return acc; }\no.init(); pure(1); impure();\n`) ],
];

describe('incremental scope map, noah-lsp edit sequences', () => {
	for (let c in CASES) {
		let k = c;
		it(k[0], () => {
			let reused = run(k[1]);
			if (k[2]) assert.match(true, reused > 0, 'reused');
		});
	}
});
