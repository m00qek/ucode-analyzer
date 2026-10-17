import { describe, it, assert, mock, beforeEach } from 'utest';
import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { resolveDoc } from 'ucode_analyzer.code_analysis.doc_resolver';
import { makeScope } from 'ucode_analyzer.code_analysis.types.scope';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';

let _parser = ts.newParser(ts.ucode());
function parse(text) { return ts.parse(_parser, text); }

let _config = { workspaceDir: '/app', selfSrcDir: '/app/src/ucode_analyzer', workspace: { libraryPaths: ['src'] } };

let URI_A = 'file:///app/src/a.uc';
let URI_B = 'file:///app/src/b.uc';

beforeEach(() => {
	dag.init(_config);
	dag.remove(URI_A);
	dag.remove(URI_B);
	invalidateUri(URI_A);
	invalidateUri(URI_B);
});

// The first identifier named `name` anywhere in the tree.
function firstIdent(root, source, name) {
	let found = null;
	function walk(n) {
		if (found) return;
		if (ts.nodeType(n) === 'identifier' && ts.text(n, source) === name) { found = n; return; }
		for (let i = 0; i < ts.namedChildCount(n); i++) walk(ts.namedChild(n, i));
	}
	walk(root);
	return found;
}

describe('doc_resolver — resolveDoc precedence', () => {
	it('resolves an own-file export\'s JSDoc', () => {
		let src = "/** greets politely */\nexport function greet() {};\n";
		let tree = parse(src);
		dag.add(URI_A, src, tree);

		let node = firstIdent(ts.rootNode(tree), src, 'greet');
		let r = resolveDoc(URI_A, node, src, makeScope(null));
		assert.match(true, r.doc !== null);
		assert.match(URI_A, r.modUri);
	});

	it('resolves an imported name to the declaring module\'s JSDoc', () => {
		let srcA = "/** the answer */\nexport function answer() {};\n";
		let srcB = "import { answer } from 'a';\nanswer;\n";

		dag.add(URI_A, srcA, parse(srcA));
		// Make 'a' resolve to URI_A on disk so B's import edge points at it.
		mock.global.patch('fs', { data: { '/app/src/a.uc': srcA } });
		let treeB = parse(srcB);
		dag.add(URI_B, srcB, treeB);
		mock.global.unpatch('fs');

		let node = firstIdent(ts.rootNode(treeB), srcB, 'answer');
		let r = resolveDoc(URI_B, node, srcB, makeScope(null));
		assert.match(true, r.doc !== null);
		assert.match(URI_A, r.modUri);   // doc comes from the declaring module, not B
	});

	it('returns nulls for an identifier with no documentation', () => {
		let src = "let x = 1;\nx;\n";
		let tree = parse(src);
		dag.add(URI_A, src, tree);

		let node = firstIdent(ts.rootNode(tree), src, 'x');
		let r = resolveDoc(URI_A, node, src, makeScope(null));
		assert.match(null, r.doc);
		assert.match(null, r.modUri);
	});

	it('returns nulls for a property_identifier not on a member_expression', () => {
		// A bare shorthand/property outside obj.prop has no resolvable owner.
		let src = "let o = { foo: 1 };\n";
		let tree = parse(src);
		dag.add(URI_A, src, tree);

		// The `foo` key is a property_identifier whose parent is a `pair`, not a
		// member_expression — resolveDoc must bail cleanly.
		let node = null;
		function walk(n) {
			if (node) return;
			if (ts.nodeType(n) === 'property_identifier') { node = n; return; }
			for (let i = 0; i < ts.namedChildCount(n); i++) walk(ts.namedChild(n, i));
		}
		walk(ts.rootNode(tree));
		if (node) {
			let r = resolveDoc(URI_A, node, src, makeScope(null));
			assert.match(null, r.doc);
			assert.match(null, r.modUri);
		}
	});
});
