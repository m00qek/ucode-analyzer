import * as ts from 'tree_sitter';
import { buildLineTable } from 'ucode_language_server.positions';

let _parser = ts.newParser(ts.ucode());
let _documents = {};

export function open(uri, text, version) {
	_documents[uri] = {
		uri,
		text,
		version,
		tree: ts.parse(_parser, text),
		lineTable: buildLineTable(text),
	};
};

export function change(uri, changes, version) {
	let doc = _documents[uri];

	if (!doc)
		return;

	let text = changes[0].text;

	_documents[uri] = {
		uri,
		text,
		version,
		tree: ts.parse(_parser, text),
		lineTable: buildLineTable(text),
	};
};

export function get(uri) {
	return _documents[uri];
};

export function close(uri) {
	delete _documents[uri];
};
