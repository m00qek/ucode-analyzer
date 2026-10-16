import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'code_analysis.documents';
import { positionToOffset } from 'code_analysis.positions';
import { actionsFor } from 'language_server.handlers.code_actions.use_optional_chain';
import { typeErrors } from 'code_analysis.diagnostics.type_errors';

let URI = 'file:///test.uc';

afterEach(() => documents.close(URI));

// The text after applying every edit of the first action (edits are disjoint).
function fixed(text) {
	documents.open(URI, text, 1);
	let doc = documents.get(URI);
	let diags = filter(typeErrors(URI, doc), (d) => d.code === 'may-be-null');
	let actions = actionsFor(URI, doc, diags);
	if (!length(actions)) return null;
	let edits = sort([...actions[0].edit.changes[URI]], (a, b) =>
		positionToOffset(text, doc.lineTable, b.range.start) - positionToOffset(text, doc.lineTable, a.range.start));
	for (let e in edits) {
		let s = positionToOffset(text, doc.lineTable, e.range.start);
		let t = positionToOffset(text, doc.lineTable, e.range.end);
		text = substr(text, 0, s) + e.newText + substr(text, t);
	}
	return text;
}

let P = "/** @param {?{ a: int }} o */\nfunction f(o) {\n";

describe('use_optional_chain', () => {
	it('turns o.a into o?.a', () => {
		assert.match(P + "\treturn o?.a;\n}\n", fixed(P + "\treturn o.a;\n}\n"));
	});

	it('turns o[0] into o?.[0]', () => {
		let Q = "/** @param {?array} o */\nfunction f(o) {\n";
		assert.match(Q + "\treturn o?.[0];\n}\n", fixed(Q + "\treturn o[0];\n}\n"));
	});

	it('keeps whitespace and comments between the object and the dot', () => {
		assert.match(P + "\treturn o /* c */ ?.a;\n}\n", fixed(P + "\treturn o /* c */ .a;\n}\n"));
	});

	it('offers nothing for a write target', () => {
		assert.match(null, fixed(P + "\to.a = 1;\n}\n"));
		assert.match(null, fixed(P + "\to.a++;\n}\n"));
	});

	it('is a quickfix tied to its diagnostic', () => {
		documents.open(URI, P + "\treturn o.a;\n}\n", 1);
		let doc = documents.get(URI);
		let diags = typeErrors(URI, doc);
		let a = actionsFor(URI, doc, diags)[0];
		assert.match('quickfix', a.kind);
		assert.match(diags, a.diagnostics);
		assert.match("Use optional chaining: 'o?.'", a.title);
	});
});
