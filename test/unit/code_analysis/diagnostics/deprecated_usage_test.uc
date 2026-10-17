import { describe, it, assert, beforeEach, afterEach, prop, gen, contains } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { deprecatedUsage } from 'ucode_analyzer.code_analysis.diagnostics.deprecated_usage';

let URI   = 'file:///test.uc';
let URI_B = 'file:///dep.uc';

let _config = {
	workspaceDir: '/app',
	selfSrcDir: '/app/src/ucode_analyzer',
	workspace: { libraryPaths: ['src'] },
};

beforeEach(() => dag.init(_config));

afterEach(() => {
	documents.close(URI);
	dag.remove(URI);
	dag.remove(URI_B);
});

function open(text) {
	documents.open(URI, text, 1);
	dag.add(URI, text, documents.get(URI).tree);
	return documents.get(URI);
}

describe('diagnostics — deprecated usage', () => {
	it('returns empty list when no deprecated symbols are used', () => {
		let doc = open("export function foo() {};\nfoo();\n");
		assert.match(0, length(deprecatedUsage(URI, doc)));
	});

	it('reports a hint for a call to a same-file @deprecated export', () => {
		let doc = open("/** @deprecated */\nexport function old() {};\nold();\n");
		let diags = deprecatedUsage(URI, doc);
		assert.match(1, length(diags));
		assert.match(4, diags[0].severity);  // HINT
		assert.match('Deprecated', diags[0].message);
	});

	it('includes DiagnosticTag.Deprecated (tag=2) on the diagnostic', () => {
		let doc = open("/** @deprecated */\nexport function old() {};\nold();\n");
		let diags = deprecatedUsage(URI, doc);
		assert.match(true, length(diags) >= 1);
		assert.match(contains([2]), diags[0].tags);
	});

	it('does not flag the declaration site itself', () => {
		let doc = open("/** @deprecated */\nexport function old() {};\n");
		assert.match(0, length(deprecatedUsage(URI, doc)));
	});

	it('flags a deprecated imported symbol but not a non-deprecated one', () => {
		// fixtures/deprecated.uc exports oldFn (@deprecated) and newFn (not).
		let DEP = 'file:///app/test/fixtures/deprecated.uc';
		dag.init({ workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src', 'test'] } });
		dag.addFromDisk(DEP);
		let src = "import { oldFn, newFn } from 'fixtures.deprecated';\noldFn();\nnewFn();\n";
		documents.open(URI, src, 1);
		dag.add(URI, src, documents.get(URI).tree);

		let diags = deprecatedUsage(URI, documents.get(URI));
		// only the oldFn() call is flagged; newFn() and the import_specifier are not
		assert.match(1, length(diags));
		assert.match(1, diags[0].range.start.line);   // line 1: `oldFn();`
		assert.match(0, diags[0].range.start.character);
		dag.remove(DEP);
	});

	it('does not flag import_specifier binding names', () => {
		let src = "import { old } from 'some.module';\n";
		documents.open(URI, src, 1);
		dag.add(URI, src, documents.get(URI).tree);
		// Even if 'old' were deprecated, the import_specifier site must not be flagged.
		// With an unresolvable module the DAG has no doc, so 0 diags expected.
		assert.match(0, length(deprecatedUsage(URI, documents.get(URI))));
	});

	it('reports the correct range for the deprecated identifier', () => {
		let doc = open("/** @deprecated */\nexport function old() {};\nold();\n");
		let diags = deprecatedUsage(URI, doc);
		assert.match(1, length(diags));
		assert.match(2, diags[0].range.start.line);   // 0-indexed: line 2 is 'old();'
		assert.match(0, diags[0].range.start.character);
	});
});

// The candidate-name gate (deprecatedNames) is a perf prefilter whose failure
// mode is silently dropping diagnostics. This property is a positive oracle: we
// generate a module with known @deprecated and plain exports plus a body of
// references, and assert the gate flags ALL-AND-ONLY the deprecated references.
// If deprecatedNames() ever under-populates, a deprecated reference goes
// unflagged and the property fails (with a shrunk counterexample).
describe('diagnostics — deprecated usage: gate flags all-and-only deprecated refs', () => {
	// spec: { nDep, nOk, refs[] } → { src, expected } where expected is the number
	// of references that point at a deprecated name.
	function buildDoc(spec) {
		let src = "";
		for (let i = 0; i < spec.nDep; i++)
			src += sprintf("/** @deprecated */\nexport function dep%d() {};\n", i);
		for (let i = 0; i < spec.nOk; i++)
			src += sprintf("export function ok%d() {};\n", i);
		let total = spec.nDep + spec.nOk, expected = 0;
		for (let r in spec.refs) {
			let idx = r % total;               // nDep >= 1 so total >= 1
			if (idx < spec.nDep) { src += sprintf("dep%d;\n", idx); expected++; }
			else                 { src += sprintf("ok%d;\n", idx - spec.nDep); }
		}
		return { src, expected };
	}

	prop("flags exactly the references to deprecated names",
		gen.record({
			nDep: gen.int(1, 3),
			nOk:  gen.int(0, 3),
			refs: gen.array(gen.int(0, 20), { min_len: 0, max_len: 8 }),
		}),
		(spec, ctx) => {
			let d = buildDoc(spec);
			ctx.classify("no refs",   length(spec.refs) === 0);
			ctx.classify("has ok",    spec.nOk > 0);
			dag.init(_config);
			documents.open(URI, d.src, 1);
			dag.add(URI, d.src, documents.get(URI).tree);
			let diags = deprecatedUsage(URI, documents.get(URI));
			documents.close(URI);
			dag.remove(URI);
			assert.match(d.expected, length(diags));
		});
});
