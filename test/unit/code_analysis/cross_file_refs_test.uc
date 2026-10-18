import { describe, it, assert, afterEach, mock, any_order } from 'utest';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { resolveExportIdentity, crossFileRefsOf, crossFileSearch, searchEntry } from 'ucode_analyzer.code_analysis.cross_file_refs';
import { cursors, locate } from 'cursor';
import * as fixture from 'fixture';

dag.init(fixture.config());

// The library the others import (`cfr_lib`), and its importers.
let LIB = cursors("export function $0$1foo$2() { return $3foo$4(); };\n" +
	"export const $5other$6 = 1;\nlet $7a$8 = 2;\nexport { a as b };\n");
let NAMED     = cursors("import { $0$1foo$2 } from 'cfr_lib';\n$3foo$4();\n$5foo$6;\n");
let ALIASED   = cursors("import { $7other, $1foo$2 as $3bar$4 } from 'cfr_lib';\n$5bar$6();\nfoo;\n");
let NS        = cursors("import * as $0ns from 'cfr_lib';\nns.$1foo$2();\nns.other;\nns.$3foo$4;\n");
let UNRELATED = cursors("import { other } from 'cfr_lib';\nother;\n");

let URI = {
	lib: fixture.uri('cfr_lib.uc'), named: fixture.uri('cfr_named.uc'), aliased: fixture.uri('cfr_aliased.uc'),
	ns: fixture.uri('cfr_ns.uc'), unrelated: fixture.uri('cfr_unrelated.uc'),
};
let ALL = { 'cfr_lib.uc': LIB, 'cfr_named.uc': NAMED, 'cfr_aliased.uc': ALIASED,
	'cfr_ns.uc': NS, 'cfr_unrelated.uc': UNRELATED };

let indexed = [];

// Index files ({ path: cursors() result }) in the DAG, their imports resolving
// to each other through a mocked fs, and open them.
function index(files) {
	let data = {};
	for (let rel, src in files) data[fixture.WORKSPACE + '/' + rel] = src.text;
	mock.global.patch('fs', { data });
	for (let rel, src in files) dag.add(fixture.uri(rel), src.text, mode.parse(src.text));
	mock.global.unpatch('fs');
	for (let rel, src in files) {
		documents.open(fixture.uri(rel), src.text, 1);
		push(indexed, fixture.uri(rel));
	}
}

function cleanup() {
	for (let uri in indexed) {
		documents.close(uri);
		dag.remove(uri);
	}
	indexed = [];
}

afterEach(cleanup);

function identityAt(uri, offset) {
	return resolveExportIdentity(uri, documents.get(uri), offset);
}

// An identity a rename follows, as resolveExportIdentity returns it.
function id(declaringUri, exportName) {
	return { declaringUri, exportName, rename: true, onAlias: false };
}

function span(src, a, b) {
	return { start: src.at[a], end: src.at[b] };
}

function entry(uri, refRanges, renameRanges) {
	return { uri, refRanges: any_order(refRanges), renameRanges: any_order(renameRanges ?? refRanges) };
}

describe('resolveExportIdentity — in an importer', () => {
	it('resolves a named import binding and its uses to the declaring file', () => {
		index(ALL);
		let want = id(URI.lib, 'foo');
		assert.match(want, identityAt(URI.named, NAMED.offset[0]));
		assert.match(want, identityAt(URI.named, NAMED.offset[3]));
		assert.match(want, identityAt(URI.named, NAMED.offset[5]));
	});

	it('resolves the unaliased name of a mixed import list', () => {
		index(ALL);
		assert.match(id(URI.lib, 'other'), identityAt(URI.aliased, ALIASED.offset[7]));
	});

	it('resolves an aliased import, which a rename of the alias keeps', () => {
		index(ALL);
		let want = { declaringUri: URI.lib, exportName: 'foo', rename: false, onAlias: false };
		assert.match(want, identityAt(URI.aliased, ALIASED.offset[3]));
		assert.match(want, identityAt(URI.aliased, ALIASED.offset[5]));
	});

	it('does not resolve a namespace alias or its members', () => {
		index(ALL);
		assert.match(null, identityAt(URI.ns, NS.offset[0]));
		assert.match(null, identityAt(URI.ns, NS.offset[1]));
	});

	it('does not resolve an import of a name the module lacks', () => {
		// Other files importing it import nothing they share.
		let src = cursors("import { $0missing } from 'cfr_lib';\n$1missing();\n");
		index({ 'cfr_lib.uc': LIB, 'cfr_missing.uc': src });
		assert.match(null, identityAt(fixture.uri('cfr_missing.uc'), src.offset[0]));
		assert.match(null, identityAt(fixture.uri('cfr_missing.uc'), src.offset[1]));
	});

	it('does not resolve an import of a field only require() reaches', () => {
		let lib = cursors("return { f: 1 };\n");
		let src = cursors("import { $0f } from 'cfr_legacy';\nf;\n");
		index({ 'cfr_legacy.uc': lib, 'cfr_legacy_user.uc': src });
		assert.match(null, identityAt(fixture.uri('cfr_legacy_user.uc'), src.offset[0]));
	});

	it('does not resolve a default import, whose remote name differs', () => {
		let src = cursors("import $0d from 'cfr_lib';\nd;\n");
		index({ 'cfr_lib.uc': LIB, 'cfr_default.uc': src });
		assert.match(null, identityAt(fixture.uri('cfr_default.uc'), src.offset[0]));
	});

	it('does not resolve an import of a module that is not found', () => {
		let src = cursors("import { $0foo } from 'cfr_nowhere';\nfoo;\n");
		index({ 'cfr_lost.uc': src });
		assert.match(null, identityAt(fixture.uri('cfr_lost.uc'), src.offset[0]));
	});
});

describe('resolveExportIdentity — in the declaring file', () => {
	it('resolves an exported declaration and its uses', () => {
		index(ALL);
		let want = id(URI.lib, 'foo');
		assert.match(want, identityAt(URI.lib, LIB.offset[0]));
		assert.match(want, identityAt(URI.lib, LIB.offset[3]));
		assert.match(id(URI.lib, 'other'), identityAt(URI.lib, LIB.offset[5]));
	});

	it('resolves a name exported by an export clause', () => {
		let src = cursors("function $0greet() {}\nexport { greet };\n");
		index({ 'cfr_clause.uc': src });
		assert.match(id(fixture.uri('cfr_clause.uc'), 'greet'), identityAt(fixture.uri('cfr_clause.uc'), src.offset[0]));
	});

	it('resolves a name exported under an alias to the alias, which a rename of it keeps', () => {
		// `let a … export { a as b }`: renaming a leaves the export named b.
		index(ALL);
		assert.match({ declaringUri: URI.lib, exportName: 'b', rename: false, onAlias: false },
			identityAt(URI.lib, LIB.offset[7]));
	});

	it('resolves an export alias, which has no references of its own', () => {
		let src = cursors("let a = 2;\nexport { a as $0b };\n");
		index({ 'cfr_alias_at.uc': src });
		assert.match({ declaringUri: fixture.uri('cfr_alias_at.uc'), exportName: 'b', rename: true, onAlias: true },
			identityAt(fixture.uri('cfr_alias_at.uc'), src.offset[0]));
	});

	it('returns null for a local, an undeclared name, or no identifier', () => {
		let src = cursors("let $0x = 1;\n$1print(x);\n$2;\n");
		index({ 'cfr_local.uc': src });
		for (let n in [ 0, 1, 2 ])
			assert.match(null, identityAt(fixture.uri('cfr_local.uc'), src.offset[n]), n);
	});

	it('returns null for a file the DAG does not know', () => {
		let src = cursors("export function $0f() {}\n");
		let uri = fixture.uri('cfr_unindexed.uc');
		documents.open(uri, src.text, 1);
		assert.match(null, identityAt(uri, src.offset[0]));
		documents.close(uri);
	});
});

describe('crossFileRefsOf', () => {
	it('from an importer: the declaring file and the other importers, by import form', () => {
		index(ALL);
		assert.match(any_order([
			entry(URI.lib, [ span(LIB, 1, 2), span(LIB, 3, 4) ]),
			// An aliased import references the alias, but a rename changes only
			// the remote name.
			entry(URI.aliased, [ span(ALIASED, 3, 4), span(ALIASED, 5, 6) ], [ span(ALIASED, 1, 2) ]),
			entry(URI.ns, [ span(NS, 1, 2), span(NS, 3, 4) ]),
		]), crossFileRefsOf(URI.lib, 'foo', URI.named));
	});

	it('from the declaring file: every importer of the name, not the file itself', () => {
		index(ALL);
		assert.match(any_order([
			entry(URI.named, [ span(NAMED, 1, 2), span(NAMED, 3, 4), span(NAMED, 5, 6) ]),
			entry(URI.aliased, [ span(ALIASED, 3, 4), span(ALIASED, 5, 6) ], [ span(ALIASED, 1, 2) ]),
			entry(URI.ns, [ span(NS, 1, 2), span(NS, 3, 4) ]),
		]), crossFileRefsOf(URI.lib, 'foo', URI.lib));
	});

	it('with nothing excluded, includes the declaring file', () => {
		index({ 'cfr_lib.uc': LIB, 'cfr_named.uc': NAMED });
		assert.match(any_order([
			entry(URI.lib, [ span(LIB, 1, 2), span(LIB, 3, 4) ]),
			entry(URI.named, [ span(NAMED, 1, 2), span(NAMED, 3, 4), span(NAMED, 5, 6) ]),
		]), crossFileRefsOf(URI.lib, 'foo', null));
	});

	it('is empty when nothing imports the name', () => {
		index({ 'cfr_lib.uc': LIB, 'cfr_unrelated.uc': UNRELATED });
		assert.match([], crossFileRefsOf(URI.lib, 'foo', URI.lib));
	});

	it('finds the importers of a name the module lacks, and no declaration', () => {
		let src = cursors("import { $1missing$2 } from 'cfr_lib';\n$3missing$4();\n");
		index({ 'cfr_lib.uc': LIB, 'cfr_missing.uc': src });
		assert.match([ entry(fixture.uri('cfr_missing.uc'), [ span(src, 1, 2), span(src, 3, 4) ]) ],
			crossFileRefsOf(URI.lib, 'missing', null));
	});

	it('skips an importer that can be neither found open nor read', () => {
		index({ 'cfr_lib.uc': LIB, 'cfr_named.uc': NAMED });
		documents.close(URI.named);   // and not on disk
		assert.match([ entry(URI.lib, [ span(LIB, 1, 2), span(LIB, 3, 4) ]) ],
			crossFileRefsOf(URI.lib, 'foo', null));
	});

	it('finds a namespace member re-exported by another module, and that module\'s importers', () => {
		let deep = fixture.uri('reexport/deep.uc'), wrapper = fixture.uri('reexport/wrapper.uc');
		dag.addFromDisk(deep);
		dag.addFromDisk(wrapper);
		push(indexed, deep, wrapper);
		let user = cursors("import { $1thing$2 } from 'reexport.wrapper';\n$3thing$4();\n");
		index({ 'cfr_user.uc': user });

		// `export const thing = deep.thing`: its `thing` property.
		let start = locate(fixture.read('reexport/wrapper.uc'), 'deep.thing', 0, 5);
		let end = { line: start.line, character: start.character + 5 };
		assert.match([
			entry(wrapper, [ { start, end } ]),
			entry(fixture.uri('cfr_user.uc'), [ span(user, 1, 2), span(user, 3, 4) ]),
		], crossFileRefsOf(deep, 'thing', deep));
	});

	it('lists each reference once for a file importing the module twice', () => {
		let src = cursors("import { $1foo$2 } from 'cfr_lib';\nimport * as ns from 'cfr_lib';\n$3foo$4(ns.$5foo$6);\n");
		index({ 'cfr_lib.uc': LIB, 'cfr_both.uc': src });
		assert.match([ entry(fixture.uri('cfr_both.uc'), [ span(src, 1, 2), span(src, 3, 4), span(src, 5, 6) ]) ],
			crossFileRefsOf(URI.lib, 'foo', URI.lib));
	});

	it('renames only the exported name of an aliased export', () => {
		// `export { a as b }`, renamed from an importer of b: the lib's local `a`
		// must stay, or `export { c as b }` no longer exports what is imported.
		// Its references are a's.
		let lib = cursors("let $1a$2 = 2;\nexport { $3a$4 as $5b$6 };\n");
		let user = cursors("import { b } from 'cfr_alias';\nb;\n");
		index({ 'cfr_alias.uc': lib, 'cfr_alias_user.uc': user });
		assert.match([ entry(fixture.uri('cfr_alias.uc'), [ span(lib, 1, 2), span(lib, 3, 4) ], [ span(lib, 5, 6) ]) ],
			crossFileRefsOf(fixture.uri('cfr_alias.uc'), 'b', fixture.uri('cfr_alias_user.uc')));
	});

	it('does not count a member of a local that shadows the namespace alias', () => {
		let src = cursors("import * as ns from 'cfr_lib';\nns.$1foo$2();\nfunction f(ns) { return ns.foo; }\n");
		index({ 'cfr_lib.uc': LIB, 'cfr_shadow.uc': src });
		assert.match([ entry(fixture.uri('cfr_shadow.uc'), [ span(src, 1, 2) ]) ],
			crossFileRefsOf(URI.lib, 'foo', URI.lib));
	});
});

// A chain cfr_a → cfr_b → cfr_c of modules re-exporting cfr_a's t: the
// files, the search's entries by file.
function chain(b) {
	let files = {
		'cfr_a.uc': cursors("export function $1t$2() {};\n"),
		'cfr_b.uc': cursors(b),
		'cfr_c.uc': cursors("import { $1t$2 } from 'cfr_b';\n$3t$4();\n"),
	};
	index(files);
	return files;
}

function search(identity, excludeUri, forRename) {
	let s = crossFileSearch(identity, excludeUri, forRename);
	let out = {};
	for (let e in [ s.decl, ...map(s.items, searchEntry) ])
		if (e) out[replace(e.uri, /^.*\//, '')] = e;
	return out;
}

describe('crossFileSearch through re-exports', () => {
	it('renames through `export { t }` of an import, which is the same binding', () => {
		let f = chain("import { $1t$2 } from 'cfr_a';\nexport { $3t$4 };\n");
		let a = f['cfr_a.uc'], b = f['cfr_b.uc'], c = f['cfr_c.uc'];
		assert.match({
			'cfr_a.uc': entry(fixture.uri('cfr_a.uc'), [ span(a, 1, 2) ]),
			'cfr_b.uc': entry(fixture.uri('cfr_b.uc'), [ span(b, 1, 2), span(b, 3, 4) ]),
			'cfr_c.uc': entry(fixture.uri('cfr_c.uc'), [ span(c, 1, 2), span(c, 3, 4) ]),
		}, search(id(fixture.uri('cfr_a.uc'), 't'), null, true));
	});

	it('finds, but does not rename, the importers of a re-export under its own binding', () => {
		for (let b in [ "import * as m from 'cfr_a';\nexport const t = m.$1t$2;\n",
		                "import { $1t$2 as u } from 'cfr_a';\nexport { u as t };\n" ]) {
			let f = chain(b);
			assert.match([ 'cfr_a.uc', 'cfr_b.uc', 'cfr_c.uc' ],
				sort(keys(search(id(fixture.uri('cfr_a.uc'), 't'), null, false))), b);
			assert.match([ 'cfr_a.uc', 'cfr_b.uc' ],
				sort(keys(search(id(fixture.uri('cfr_a.uc'), 't'), null, true))), b);
			cleanup();
		}
	});

	it('finds, from an importer of the re-export, the module that declares it', () => {
		for (let b in [ "import * as m from 'cfr_a';\nexport const t = m.$1t$2;\n",
		                "import { $1t$2 as u } from 'cfr_a';\nexport { u as t };\n" ]) {
			let a = chain(b)['cfr_a.uc'];
			let found = search(id(fixture.uri('cfr_b.uc'), 't'), fixture.uri('cfr_c.uc'), false);
			assert.match([ 'cfr_a.uc', 'cfr_b.uc' ], sort(keys(found)), b);
			assert.match(entry(fixture.uri('cfr_a.uc'), [ span(a, 1, 2) ]), found['cfr_a.uc'], b);
			// A rename changes b's own t.
			assert.match([ 'cfr_b.uc' ], keys(search(id(fixture.uri('cfr_b.uc'), 't'), fixture.uri('cfr_c.uc'), true)), b);
			cleanup();
		}
	});

	it('renames, from an importer of `export { t }`, up to the module that declares it', () => {
		let f = chain("import { $1t$2 } from 'cfr_a';\nexport { $3t$4 };\n");
		let a = f['cfr_a.uc'], b = f['cfr_b.uc'];
		assert.match({
			'cfr_a.uc': entry(fixture.uri('cfr_a.uc'), [ span(a, 1, 2) ]),
			'cfr_b.uc': entry(fixture.uri('cfr_b.uc'), [ span(b, 1, 2), span(b, 3, 4) ]),
		}, search(id(fixture.uri('cfr_b.uc'), 't'), fixture.uri('cfr_c.uc'), true));
	});

	it('stops at a cycle of re-exports, having searched each module once', () => {
		let a = cursors("import { $1t$2 } from 'cfr_cy_b';\nexport { $3t$4 };\n");
		let b = cursors("import { $1t$2 } from 'cfr_cy_a';\nexport { $3t$4 };\n");
		index({ 'cfr_cy_a.uc': a, 'cfr_cy_b.uc': b });
		let s = crossFileSearch(id(fixture.uri('cfr_cy_a.uc'), 't'), null, false);
		assert.match(any_order([ [ fixture.uri('cfr_cy_a.uc'), fixture.uri('cfr_cy_b.uc'), 't' ],
		                         [ fixture.uri('cfr_cy_b.uc'), fixture.uri('cfr_cy_a.uc'), 't' ] ]), s.items);
	});
});

describe('crossFileSearch of an aliased export', () => {
	let LIB2 = "let $1a$2 = 2;\nexport { $3a$4 as $5b$6 };\nexport { $7a$8 };\n";

	it('finds the importers of every name it is exported under', () => {
		let lib = cursors(LIB2);
		let ub = cursors("import { $1b$2 } from 'cfr_al';\n$3b$4;\n");
		let ua = cursors("import { $1a$2 } from 'cfr_al';\n$3a$4;\n");
		index({ 'cfr_al.uc': lib, 'cfr_al_b.uc': ub, 'cfr_al_a.uc': ua });
		let ident = resolveExportIdentity(fixture.uri('cfr_al.uc'), documents.get(fixture.uri('cfr_al.uc')), lib.offset[1]);
		assert.match(id(fixture.uri('cfr_al.uc'), 'a'), ident);
		assert.match({
			'cfr_al_a.uc': entry(fixture.uri('cfr_al_a.uc'), [ span(ua, 1, 2), span(ua, 3, 4) ]),
			'cfr_al_b.uc': entry(fixture.uri('cfr_al_b.uc'), [ span(ub, 1, 2), span(ub, 3, 4) ]),
		}, search(ident, fixture.uri('cfr_al.uc'), false));
		// A rename of a keeps b.
		assert.match([ 'cfr_al_a.uc' ], keys(search(ident, fixture.uri('cfr_al.uc'), true)));
	});

	it('renames, from the alias, the alias and its importers only', () => {
		let lib = cursors(LIB2);
		let ub = cursors("import { $1b$2 } from 'cfr_al';\n$3b$4;\n");
		let ua = cursors("import { a } from 'cfr_al';\na;\n");
		index({ 'cfr_al.uc': lib, 'cfr_al_b.uc': ub, 'cfr_al_a.uc': ua });
		let ident = resolveExportIdentity(fixture.uri('cfr_al.uc'), documents.get(fixture.uri('cfr_al.uc')), lib.offset[5]);
		assert.match({
			'cfr_al.uc': entry(fixture.uri('cfr_al.uc'), [ span(lib, 1, 2), span(lib, 3, 4), span(lib, 7, 8) ], [ span(lib, 5, 6) ]),
			'cfr_al_b.uc': entry(fixture.uri('cfr_al_b.uc'), [ span(ub, 1, 2), span(ub, 3, 4) ]),
		}, search(ident, fixture.uri('cfr_al.uc'), true));
	});
});
