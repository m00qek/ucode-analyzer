import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { positionToOffset } from 'ucode_analyzer.code_analysis.positions';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { undefinedVars } from 'ucode_analyzer.code_analysis.diagnostics.undefined_var';
import { actionsFor } from 'ucode_analyzer.language_server.handlers.code_actions.add_missing_import';
import * as fixture from 'fixture';

let URI = fixture.uri('t.uc');

dag.init(fixture.config());
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);
dag.addFromDisk(fixture.uri('greet.uc'));
dag.addFromDisk(fixture.uri('legacy_mod.uc'));

afterEach(() => documents.close(URI));

function actions(text) {
	documents.open(URI, text, 1);
	let doc = documents.get(URI);
	return actionsFor(URI, doc, undefinedVars(doc));
}

function applied(text, action) {
	let doc = documents.get(URI);
	let e = action.edit.changes[URI][0];
	let s = positionToOffset(text, doc.lineTable, e.range.start);
	let t = positionToOffset(text, doc.lineTable, e.range.end);
	return substr(text, 0, s) + e.newText + substr(text, t);
}

describe('add_missing_import', () => {
	it('imports an ES export, not a legacy return-object field of the same name', () => {
		let text = "greet();\n";
		let a = actions(text);
		assert.match(["Import 'greet' from 'greet'"], map(a, (x) => x.title));
		assert.match("import { greet } from 'greet';\ngreet();\n", applied(text, a[0]));
		assert.match(true, a[0].isPreferred);
	});

	it('extends an existing import from the same module', () => {
		let text = "import { other } from 'greet';\ngreet();\n";
		assert.match("import { other, greet } from 'greet';\ngreet();\n", applied(text, actions(text)[0]));
	});

	it('adds a line after the last import, in its quote style', () => {
		let text = "import * as fs from \"fs\";\ngreet();\n";
		assert.match("import * as fs from \"fs\";\nimport { greet } from \"greet\";\ngreet();\n", applied(text, actions(text)[0]));
	});

	it('keeps a shebang first', () => {
		let text = "#!/usr/bin/ucode\ngreet();\n";
		assert.match("#!/usr/bin/ucode\nimport { greet } from 'greet';\ngreet();\n", applied(text, actions(text)[0]));
	});

	it('imports a declaration-module function', () => {
		let text = "readfile('/x');\n";
		dag.addFromDisk(dag.resolveSpecifier('fs'));
		assert.match(["Import 'readfile' from 'fs'"], map(actions(text), (x) => x.title));
	});

	it('offers nothing for a name no module exports, or in a template', () => {
		assert.match([], actions("nosuchname();\n"));
		assert.match([], actions("{% greet(); %}\n"));
	});
});
