'use strict';

import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import * as fs from 'fs';
import { isTemplate } from 'ucode_analyzer.code_analysis.mode';

function walkFiles(dir, ext) {
	let results = [];
	let d = fs.opendir(dir);
	if (!d) return results;
	let entry;
	while ((entry = d.read()) !== null) {
		if (entry === '.' || entry === '..') continue;
		let path = dir + '/' + entry;
		let st = fs.stat(path);
		if (!st) continue;
		if (st.type === 'directory')
			for (let f in walkFiles(path, ext)) push(results, f);
		else if (st.type === 'file' && substr(path, -length(ext)) === ext)
			push(results, path);
	}
	d.close();
	return results;
}


describe('ucode source files parse without errors', () => {
	let script   = ts.newParser(ts.ucode());
	let template = ts.newParser(ts.markup());
	let files = sort(walkFiles('/app/src', '.uc'));

	for (let file in files) {
		// A closure sees a loop variable's last value; a block's `let` is per pass.
		let path = file;
		it(path, () => {
			let src = fs.readfile(path);
			let tree = ts.parse(isTemplate(src) ? template : script, src);
			// ERROR and MISSING nodes alike.
			assert.match(false, ts.hasError(ts.rootNode(tree)));
		});
	}
});
