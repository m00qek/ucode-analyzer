import * as ts from 'tree_sitter';
import * as fs from 'fs';
import { parseDoc } from 'ucode_language_server.doc_parser';

// Return the text of the /** */ block immediately before stmt among root's
// children, or null if none. A // comment or any other statement resets.
function precedingDocText(stmt, root, text) {
	let stmtStart = ts.startByte(stmt);
	let found = null;
	let children = ts.children(root);
	for (let i = 0; i < length(children); i++) {
		let c = children[i];
		if (ts.startByte(c) >= stmtStart) break;
		if (ts.nodeType(c) === 'comment') {
			let txt = ts.text(c, text);
			found = (substr(txt, 0, 3) === '/**') ? txt : null;
		} else if (ts.isNamed(c)) {
			found = null;
		}
	}
	return found;
}

function dotToSlash(s) {
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		out += (c === '.') ? '/' : c;
	}
	return out;
}

// Return 'function' if name is declared as a function at the top level, else 'let'.
function localDeclKind(root, text, name) {
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		let nt = ts.nodeType(stmt);
		if (nt === 'function_declaration') {
			let nameNode = ts.namedChild(stmt, 0);
			if (nameNode && ts.text(nameNode, text) === name) return 'function';
		} else if (nt === 'lexical_declaration') {
			for (let j = 0; j < ts.namedChildCount(stmt); j++) {
				let vd = ts.namedChild(stmt, j);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let nameNode = ts.namedChild(vd, 0);
				if (!nameNode || ts.text(nameNode, text) !== name) continue;
				let init = ts.childByField(vd, 'value');
				if (!init) return 'let';
				let it = ts.nodeType(init);
				return (it === 'arrow_function' || it === 'function_expression') ? 'function' : 'let';
			}
		}
	}
	return 'let';
}

// Extracts the module specifier string from an import_statement node.
function importSpecifier(stmt, text) {
	for (let i = 0; i < ts.childCount(stmt); i++) {
		let child = ts.child(stmt, i);
		if (ts.nodeType(child) !== 'string') continue;
		for (let j = 0; j < ts.childCount(child); j++) {
			let frag = ts.child(child, j);
			if (ts.nodeType(frag) === 'string_fragment')
				return ts.text(frag, text);
		}
	}
	return null;
}

export function extractExports(text, tree) {
	let result = [];
	let root = ts.rootNode(tree);

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'export_statement') continue;

		let decl = ts.namedChild(stmt, 0);
		if (!decl) continue;

		let declType = ts.nodeType(decl);

		let docText = precedingDocText(stmt, root, text);
		let doc = docText ? parseDoc(docText) : null;

		if (declType === 'function_declaration') {
			let nameNode = ts.namedChild(decl, 0);
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				push(result, { name: ts.text(nameNode, text), kind: 'function', doc });

		} else if (declType === 'lexical_declaration') {
			let kind = 'let';
			for (let j = 0; j < ts.childCount(decl); j++) {
				let child = ts.child(decl, j);
				if (!ts.isNamed(child) && ts.nodeType(child) === 'const') {
					kind = 'const';
					break;
				}
			}
			for (let j = 0; j < ts.namedChildCount(decl); j++) {
				let varDecl = ts.namedChild(decl, j);
				if (ts.nodeType(varDecl) !== 'variable_declarator') continue;
				let nameNode = ts.namedChild(varDecl, 0);
				if (nameNode && ts.nodeType(nameNode) === 'identifier')
					push(result, { name: ts.text(nameNode, text), kind, doc });
			}
		} else if (declType === 'export_clause') {
			for (let j = 0; j < ts.namedChildCount(decl); j++) {
				let spec = ts.namedChild(decl, j);
				if (ts.nodeType(spec) !== 'export_specifier') continue;
				// last named child is the exported name (handles both `{ name }` and `{ local as name }`)
				let count = ts.namedChildCount(spec);
				let nameNode = ts.namedChild(spec, count - 1);
				if (!nameNode || ts.nodeType(nameNode) !== 'identifier') continue;
				let name = ts.text(nameNode, text);
				push(result, { name, kind: localDeclKind(root, text, name), doc: null });
			}
		}
	}

	return result;
};

export function extractImports(text, tree) {
	let result = [];
	let root = ts.rootNode(tree);

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let stmt = ts.namedChild(root, i);
		if (ts.nodeType(stmt) !== 'import_statement') continue;

		let specifier = importSpecifier(stmt, text);
		if (!specifier) continue;

		let clause = null;
		for (let j = 0; j < ts.childCount(stmt); j++) {
			let child = ts.child(stmt, j);
			if (ts.nodeType(child) === 'import_clause') { clause = child; break; }
		}
		if (!clause) continue;

		let clauseChild = ts.namedChild(clause, 0);
		if (!clauseChild) continue;

		let clauseType = ts.nodeType(clauseChild);

		if (clauseType === 'named_imports') {
			let symbols = [];
			for (let j = 0; j < ts.namedChildCount(clauseChild); j++) {
				let spec = ts.namedChild(clauseChild, j);
				if (ts.nodeType(spec) !== 'import_specifier') continue;
				let nameNode = ts.namedChild(spec, 0);
				if (nameNode) push(symbols, ts.text(nameNode, text));
			}
			push(result, { specifier, symbols, alias: null, resolvedUri: null });

		} else if (clauseType === 'namespace_import') {
			let alias = null;
			let count = ts.namedChildCount(clauseChild);
			if (count > 0) {
				let last = ts.namedChild(clauseChild, count - 1);
				if (ts.nodeType(last) === 'identifier')
					alias = ts.text(last, text);
			}
			push(result, { specifier, symbols: ['*'], alias, resolvedUri: null });
		}
	}

	return result;
};

// Resolves a module specifier to a file:// URI using the given library paths.
// libraryPaths are absolute paths. workspaceDir is the workspace root (used
// to resolve relative libraryPaths).
export function resolveModule(specifier, libraryPaths, workspaceDir) {
	let slashForm = dotToSlash(specifier) + '.uc';
	let dotForm   = specifier + '.uc';

	for (let libPath in libraryPaths) {
		let absLib = (substr(libPath, 0, 1) === '/') ? libPath : workspaceDir + '/' + libPath;
		let candidates = [absLib + '/' + slashForm, absLib + '/' + dotForm];

		for (let candidate in candidates) {
			let s = fs.stat(candidate);
			if (s && s.type === 'file')
				return 'file://' + candidate;
		}
	}

	return null;
};
