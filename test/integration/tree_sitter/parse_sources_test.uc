'use strict';

import { describe, it, assert } from 'utest';
import * as ts from 'tree_sitter';
import * as fs from 'fs';

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

function hasErrors(node) {
	if (ts.nodeType(node) === 'ERROR') return true;
	for (let c in ts.namedChildren(node))
		if (hasErrors(c)) return true;
	return false;
}

describe('ucode source files parse without errors', () => {
	let parser = ts.newParser(ts.ucode());
	let files = sort(walkFiles('/app/src', '.uc'));

	for (let path in files) {
		it(path, () => {
			let src = fs.readfile(path);
			let tree = ts.parse(parser, src);
			assert.match(false, hasErrors(ts.rootNode(tree)));
		});
	}
});
