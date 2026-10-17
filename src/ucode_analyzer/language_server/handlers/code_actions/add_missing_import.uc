import * as ts from 'tree_sitter';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { positionToOffset, offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { globalUri } from 'ucode_analyzer.code_analysis.types.dag_bridge';

// An undefined name some known module exports: import it from there.
// Scripts only (a template's imports sit inside tags). A legacy
// `return { … }` module is skipped: it loads through require(), and an
// import of it fails.

let MAX_CANDIDATES = 5;

// Specifiers of the modules that export `name`, sorted.
function exporters(name, selfUri) {
	let out = {};
	let builtins = globalUri();
	for (let uri in dag.allUris()) {
		if (uri === selfUri || uri === builtins) continue;
		for (let e in (dag.exportsOf(uri) ?? [])) {
			if (e.name !== name || e.legacy) continue;
			let spec = dag.specifierOf(uri);
			if (spec) out[spec] = true;
			break;
		}
	}
	return sort(keys(out));
}

// The edit that adds `name` to the file's imports from `spec`.
function importEdit(doc, root, name, spec) {
	let pos = (off) => offsetToPosition(doc.text, doc.lineTable, off);
	let lastImport = null, quote = "'";
	for (let stmt in mode.topLevelStatements(root)) {
		if (ts.nodeType(stmt) !== 'import_statement') continue;
		lastImport = stmt;
		let src = ts.childByField(stmt, 'source');
		if (src) quote = substr(doc.text, ts.startByte(src), 1);
		if (mode.importStmtSpecifier(stmt, doc.text) !== spec) continue;
		let named = ts.childByField(ts.childByField(stmt, 'clause'), 'named');
		if (!named) continue;
		let specs = filter(ts.namedChildren(named), (c) => ts.nodeType(c) === 'import_specifier');
		if (length(specs)) {
			let at = pos(ts.endByte(specs[-1]));
			return { range: { start: at, end: at }, newText: ', ' + name };
		}
		let at = pos(ts.startByte(named) + 1);
		return { range: { start: at, end: at }, newText: ' ' + name + ' ' };
	}
	let line = sprintf('import { %s } from %s%s%s;', name, quote, spec, quote);
	if (lastImport) {
		let at = pos(ts.endByte(lastImport));
		return { range: { start: at, end: at }, newText: '\n' + line };
	}
	let first = (substr(doc.text, 0, 2) === '#!') ? { line: 1, character: 0 } : { line: 0, character: 0 };
	return { range: { start: first, end: first }, newText: line + '\n' };
}

export function actionsFor(uri, doc, diagnostics) {
	let root = ts.rootNode(doc.tree);
	if (ts.nodeType(root) !== 'program') return [];
	let actions = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'undefined-var') continue;
		let s = positionToOffset(doc.text, doc.lineTable, diag.range.start);
		let e = positionToOffset(doc.text, doc.lineTable, diag.range.end);
		let name = substr(doc.text, s, e - s);
		let specs = exporters(name, uri);
		for (let i = 0; i < length(specs) && i < MAX_CANDIDATES; i++)
			push(actions, {
				title:       sprintf("Import '%s' from '%s'", name, specs[i]),
				kind:        'quickfix',
				diagnostics: [diag],
				isPreferred: length(specs) === 1,
				edit:        { changes: { [uri]: [importEdit(doc, root, name, specs[i])] } },
			});
	}

	return actions;
};
