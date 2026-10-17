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

describe('JSDoc comments in all source files parse without ucdocs errors', () => {
	let parser_ucode  = ts.newParser(ts.ucode());
	let parser_ucdocs = ts.newParser(ts.ucdocs());
	let query = ts.newQuery(ts.ucode(), '(comment) @c');

	let files = sort(walkFiles('/app/src', '.uc'));

	for (let file in files) {
		// A closure sees a loop variable's last value; a block's `let` is per pass.
		let path = file;
		it(path, () => {
			let src = fs.readfile(path);
			let tree = ts.parse(parser_ucode, src);
			let caps = ts.queryCaptures(query, ts.rootNode(tree), src);

			for (let cap in caps) {
				let text = ts.text(cap.node, src);
				if (substr(text, 0, 3) !== '/**') continue;
				let dtree = ts.parse(parser_ucdocs, text);
				assert.match(false, hasErrors(ts.rootNode(dtree)),
					'ucdocs parse error in ' + path + ': ' + text);
			}
		});
	}
});
