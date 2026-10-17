import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { stringLiteralText } from 'ucode_analyzer.code_analysis.ast_text';

// Links from module names to their files: an import's source and a literal
// require('…') argument, resolved like the import itself.

let REQUIRES = `((call_expression function: (identifier) @f arguments: (arguments . (string) @s)) (#eq? @f "require"))`;
let _query = {};

function link(doc, str, out) {
	let spec = stringLiteralText(str, doc.text);
	let target = length(spec) ? dag.resolveSpecifier(spec) : null;
	if (!target) return;
	push(out, {
		range: {
			start: offsetToPosition(doc.text, doc.lineTable, ts.startByte(str) + 1),
			end:   offsetToPosition(doc.text, doc.lineTable, ts.endByte(str) - 1),
		},
		target,
		tooltip: substr(target, 7),
	});
}

export function documentLinks(doc) {
	let root = ts.rootNode(doc.tree);
	let out = [];
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		let src = ts.childByField(stmt, 'source');
		if (src && ts.nodeType(src) === 'string') link(doc, src, out);
	}
	let lang = ts.nodeType(root) === 'markup' ? 'markup' : 'ucode';
	_query[lang] ??= ts.newQuery(lang === 'markup' ? ts.markup() : ts.ucode(), REQUIRES);
	for (let m in ts.queryMatches(_query[lang], root, doc.text))
		for (let c in m.captures)
			if (c.name === 's') link(doc, c.node, out);
	return out;
};
