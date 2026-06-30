import * as ts from 'tree_sitter';
import * as dag from 'language_server.dag.dag';
import { inferNode, globalUri } from 'language_server.types.inferrer';

// Resolve JSDoc for the node under the cursor. Tries, in order:
//   identifier          -> named import -> own-file export -> stdlib builtin
//   property_identifier -> module member -> record field
// Returns { doc, modUri } where modUri is the declaration file that owns the symbol,
// or { doc: null, modUri: null } when no documentation is found.
export function resolveDoc(uri, node, source, scope) {
	let ntype = ts.nodeType(node);

	if (ntype === 'identifier') {
		let name = ts.text(node, source);

		let imps = dag.importsOf(uri);
		if (imps) {
			for (let i = 0; i < length(imps); i++) {
				let imp = imps[i];
				if (!imp.resolvedUri || index(imp.symbols, name) < 0) continue;
				let remoteName = (imp.renames && imp.renames[name]) ?? name;
				let exp = dag.resolveExport(imp.resolvedUri, remoteName);
				if (exp && exp.doc) return { doc: exp.doc, modUri: imp.resolvedUri };
			}
		}

		let exp = dag.resolveExport(uri, name);
		if (exp && exp.doc) return { doc: exp.doc, modUri: uri };

		let bUri = globalUri();
		if (bUri) {
			let exps = dag.exportsOf(bUri);
			if (exps) {
				for (let i = 0; i < length(exps); i++)
					if (exps[i].name === name && exps[i].doc)
						return { doc: exps[i].doc, modUri: bUri };
			}
		}

		return { doc: null, modUri: null };
	}

	if (ntype === 'property_identifier') {
		let parent = ts.parent(node);
		if (!parent || ts.nodeType(parent) !== 'member_expression')
			return { doc: null, modUri: null };
		let objNode  = ts.namedChild(parent, 0);
		let propName = ts.text(node, source);
		let objType  = inferNode(objNode, source, uri, scope, 0);
		if (!objType) return { doc: null, modUri: null };
		if (objType.kind === 'nullable') objType = objType.inner;

		if (objType.kind === 'module') {
			let r = dag.resolveMember(objType.path, propName);
			if (r && r.exp.doc) return { doc: r.exp.doc, modUri: r.uri };
			return { doc: null, modUri: null };
		}

		if (objType.kind === 'record') {
			for (let i = 0; i < length(objType.fields ?? []); i++) {
				let f = objType.fields[i];
				if (f.name === propName && f.doc) return { doc: f.doc, modUri: null };
			}
		}

		return { doc: null, modUri: null };
	}

	return { doc: null, modUri: null };
};
