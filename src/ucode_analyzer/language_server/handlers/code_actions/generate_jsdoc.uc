import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition, docBearingStatement, precedingDoc } from 'ucode_analyzer.code_analysis.positions';
import { inferNode, inferParams } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { firstNamed } from 'ucode_analyzer.code_analysis.ast_text';

// On a function's first line, when it has no doc comment: insert a /** */
// with an @param per parameter and an @returns, typed by inference ({any}
// where it knows nothing). Functions: declarations, and a function or arrow
// that is the whole initializer of a single-declarator let/const.

// A type in ucdocs syntax. Records are `object`: the hover form `{ a, b }`
// lists names only and is not a type.
let docType;
docType = function(t) {
	let k = t?.kind;
	if (!t || k === 'unknown' || k === 'any') return 'any';
	if (k === 'primitive' || k === 'param') return t.name;
	if (k === 'nullable') return '?' + docType(t.inner);
	if (k === 'union') return join(' | ', map(t.members, docType));
	if (k === 'generic') return t.base + '<' + join(', ', map(t.params, docType)) + '>';
	if (k === 'ref') return length(t.params) ? t.name + '<' + join(', ', map(t.params, docType)) + '>' : t.name;
	if (k === 'record') return 'object';
	if (k === 'function') return 'function';
	if (k === 'module') return 'module:' + t.path;
	return 'any';
};

function documentable(node) {
	let t = ts.nodeType(node);
	if (t === 'function_declaration') return true;
	if (t !== 'function_expression' && t !== 'arrow_function') return false;
	let vd = ts.parent(node);
	if (!vd || ts.nodeType(vd) !== 'variable_declarator') return false;
	let value = ts.childByField(vd, 'value');
	if (!value || ts.startByte(value) !== ts.startByte(node)) return false;
	return length(filter(ts.namedChildren(ts.parent(vd)), (c) => ts.nodeType(c) === 'variable_declarator')) === 1;
}

export function actionsFor(uri, doc, range) {
	if (!range) return [];
	let root = ts.rootNode(doc.tree);
	let offset = positionToOffset(doc.text, doc.lineTable, range.start);
	// The function the cursor is in, or whose `const f = …` it is on.
	let fn = null;
	for (let n = ts.descendantAt(root, offset); n && !fn; n = ts.parent(n)) {
		let v = (ts.nodeType(n) === 'variable_declarator') ? ts.childByField(n, 'value') : null;
		if (documentable(n)) fn = n;
		else if (v && documentable(v)) fn = v;
	}
	if (!fn) return [];

	let stmt = docBearingStatement(fn).target;
	let line = offsetToPosition(doc.text, doc.lineTable, ts.startByte(stmt)).line;
	if (range.start.line !== line || precedingDoc(fn, doc.text)) return [];

	let scope = scopeAtOffset(doc.scopeMap, ts.startByte(fn));
	// `...r` is `{...T}` (T the element type), the JSDoc rest form.
	let rest = {};
	let formals = ts.childByField(fn, 'parameters');
	for (let c in (formals ? ts.namedChildren(formals) : []))
		if (ts.nodeType(c) === 'rest_element') rest[ts.text(firstNamed(c), doc.text)] = true;
	let lines = [];
	for (let p in inferParams(fn, doc.text, uri, scope)) {
		let t = p.type;
		if (rest[p.name] && t?.kind === 'generic' && t.base === 'list') t = t.params[0];
		push(lines, sprintf(' * @param {%s%s} %s', rest[p.name] ? '...' : '', docType(t), p.name));
	}
	let ret = inferNode(fn, doc.text, uri, scope, 0)?.return;
	if (ret && ret.kind !== 'unknown' && !(ret.kind === 'primitive' && ret.name === 'null'))
		push(lines, sprintf(' * @returns {%s}', docType(ret)));
	if (!length(lines)) return [];

	let lineStart = doc.lineTable[line];
	let indent = match(substr(doc.text, lineStart, ts.startByte(stmt) - lineStart), /^[ \t]*/)?.[0] ?? '';
	let text = indent + '/**\n' + join('', map(lines, (l) => indent + l + '\n')) + indent + ' */\n';
	let at = { line, character: 0 };
	return [{
		title: 'Generate JSDoc',
		kind:  'refactor.rewrite',
		edit:  { changes: { [uri]: [{ range: { start: at, end: at }, newText: text }] } },
	}];
};
