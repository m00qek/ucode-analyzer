import * as ts from 'tree_sitter';
import { positionToOffset, offsetToPosition } from 'ucode_analyzer.code_analysis.positions';

// `x.p` / `x[i]` whose object x may be null: make the access null-safe as
// `x?.p` / `x?.[i]`. Not for a write target: `x?.p = 1` and `x?.p++` are
// syntax errors in ucode (`delete x?.p` is fine).

function isWriteTarget(access) {
	let parent = ts.parent(access);
	let pt = parent ? ts.nodeType(parent) : null;
	if (pt === 'update_expression') return true;
	if (pt !== 'assignment_expression' && pt !== 'augmented_assignment_expression') return false;
	let left = ts.childByField(parent, 'left');
	return left && ts.startByte(left) === ts.startByte(access) && ts.endByte(left) === ts.endByte(access);
}

// The member/subscript access whose object spans exactly [start, end).
function accessOn(root, start, end) {
	for (let n = ts.descendantAt(root, start); n; n = ts.parent(n)) {
		let t = ts.nodeType(n);
		if (t !== 'member_expression' && t !== 'subscript_expression') continue;
		let obj = ts.childByField(n, 'object');
		if (obj && ts.startByte(obj) === start && ts.endByte(obj) === end) return n;
	}
	return null;
}

export function actionsFor(uri, doc, diagnostics) {
	let root    = ts.rootNode(doc.tree);
	let actions = [];

	for (let diag in (diagnostics ?? [])) {
		if (diag.code !== 'may-be-null') continue;
		let start  = positionToOffset(doc.text, doc.lineTable, diag.range.start);
		let end    = positionToOffset(doc.text, doc.lineTable, diag.range.end);
		let access = accessOn(root, start, end);
		if (!access || ts.childByField(access, 'optional_chain') || isWriteTarget(access)) continue;

		// The `.` or `[` right after the object: `?` goes before a `.`, `?.` before a `[`.
		let token = null;
		for (let c in ts.children(access))
			if (!ts.isNamed(c) && ts.startByte(c) >= end) { token = c; break; }
		if (!token) continue;
		let tt = ts.nodeType(token);
		if (tt !== '.' && tt !== '[') continue;

		let at = offsetToPosition(doc.text, doc.lineTable, ts.startByte(token));
		let obj = substr(doc.text, start, end - start);
		push(actions, {
			title:       sprintf("Use optional chaining: '%s?.'", obj),
			kind:        'quickfix',
			diagnostics: [diag],
			edit: {
				changes: { [uri]: [{ range: { start: at, end: at }, newText: tt === '.' ? '?' : '?.' }] },
			},
		});
	}

	return actions;
};
