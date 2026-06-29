import * as fs from 'fs';
import * as ts from 'tree_sitter';
import { extractExports, extractImports, extractTypedefs, extractModuleDoc, extractVersions, resolveModule } from 'language_server.dag.indexer';
import * as type_registry from 'language_server.types.registry';

let _parser = ts.newParser(ts.ucode());
let _config = {};
let _nodes = {};
let _outEdges = {};
let _inEdges = {};
let _openUris = {};

function uriToPath(uri) {
	return substr(uri, 7);
}

function resolvedLibPaths() {
	let ws = _config.workspace ?? {};
	let paths = ws.libraryPaths ?? ['src'];
	let workdir = _config.workspaceDir ?? '/';
	let out = [];
	for (let p in paths)
		push(out, (substr(p, 0, 1) === '/') ? p : workdir + '/' + p);
	if (_config.selfSrcDir) push(out, _config.selfSrcDir);
	for (let p in (_config.systemLibPaths ?? []))
		push(out, p);
	return out;
}

function resolveAll(imports) {
	let libs = resolvedLibPaths();
	let workdir = _config.workspaceDir ?? '/';
	for (let imp in imports)
		imp.resolvedUri = resolveModule(imp.specifier, libs, workdir);
	return imports;
}

function removeOutEdges(uri) {
	for (let target in (_outEdges[uri] ?? [])) {
		let filtered = [];
		for (let t in (_inEdges[target] ?? []))
			if (t !== uri) push(filtered, t);
		if (length(filtered) > 0)
			_inEdges[target] = filtered;
		else
			delete _inEdges[target];
	}
	delete _outEdges[uri];
}

function addOutEdges(uri, imports) {
	let targets = [];
	for (let imp in imports) {
		if (!imp.resolvedUri) continue;
		push(targets, imp.resolvedUri);
		if (!_inEdges[imp.resolvedUri]) _inEdges[imp.resolvedUri] = [];
		push(_inEdges[imp.resolvedUri], uri);
	}
	if (length(targets) > 0) _outEdges[uri] = targets;
}

function indexNode(uri, text, tree) {
	let exps = extractExports(text, tree);
	let imps = resolveAll(extractImports(text, tree));
	let moduleDoc = extractModuleDoc(text, tree);
	let versions  = extractVersions(text);
	removeOutEdges(uri);
	_nodes[uri] = { exports: exps, imports: imps, moduleDoc, versions };
	addOutEdges(uri, imps);
	extractTypedefs(uri, text, tree);
}

function readAndParse(path) {
	let f = fs.open(path, 'r');
	if (!f) return null;
	let text = f.read('all');
	f.close();
	return { text, tree: ts.parse(_parser, text) };
}

export function init(config) {
	_config = config;
	_openUris = {};
};

export function markOpen(uri) { _openUris[uri] = true; };
export function markClosed(uri) { delete _openUris[uri]; };

// Index with provided content (no cascade — used for initial workspace scan).
export function add(uri, text, tree) {
	indexNode(uri, text, tree);
};

// Index a file from disk (no cascade — used for initial workspace scan).
export function addFromDisk(uri) {
	let parsed = readAndParse(uriToPath(uri));
	if (parsed) indexNode(uri, parsed.text, parsed.tree);
};

// Re-index a file with the given content, then cascade through reverse deps.
// openDocs is an optional map of uri -> {text, tree} for currently open files;
// when provided, open dependents are re-indexed from memory instead of skipped.
// Returns the list of dependent URIs that were re-indexed (excluding uri itself).
export function update(uri, text, tree, openDocs) {
	indexNode(uri, text, tree);

	let visited = {};
	let queue = [];
	let qi = 0;
	visited[uri] = true;

	for (let dep in (_inEdges[uri] ?? []))
		if (!visited[dep]) { visited[dep] = true; push(queue, dep); }

	while (qi < length(queue)) {
		let next = queue[qi++];
		if (_openUris[next]) {
			let mem = openDocs ? openDocs[next] : null;
			if (mem) indexNode(next, mem.text, mem.tree);
		} else {
			let parsed = readAndParse(uriToPath(next));
			if (parsed) {
				indexNode(next, parsed.text, parsed.tree);
			} else {
				// File no longer on disk — cascade its reverse deps then remove it.
				let revDeps = _inEdges[next] ?? [];
				removeOutEdges(next);
				delete _nodes[next];
				delete _inEdges[next];
				delete _openUris[next];
				type_registry.removeUri(next);
				for (let dep in revDeps)
					if (!visited[dep]) { visited[dep] = true; push(queue, dep); }
				continue;
			}
		}

		for (let dep in (_inEdges[next] ?? []))
			if (!visited[dep]) { visited[dep] = true; push(queue, dep); }
	}

	return queue;
};

export function remove(uri) {
	removeOutEdges(uri);
	delete _nodes[uri];
	delete _inEdges[uri];
	delete _openUris[uri];
	type_registry.removeUri(uri);
};

export function exportsOf(uri) {
	return _nodes[uri] ? _nodes[uri].exports : null;
};

export function importsOf(uri) {
	return _nodes[uri] ? _nodes[uri].imports : null;
};

export function moduleDocOf(uri) {
	return _nodes[uri] ? _nodes[uri].moduleDoc : null;
};

export function versionsOf(uri) {
	return _nodes[uri] ? _nodes[uri].versions : null;
};

export function reverseDeps(uri) {
	return _inEdges[uri] ?? [];
};

export function allUris() {
	return keys(_nodes);
};

export function resolveSpecifier(specifier) {
	let workdir = _config.workspaceDir ?? '/';
	return resolveModule(specifier, resolvedLibPaths(), workdir);
};

export function resolveSpecifierIn(paths, specifier) {
	return resolveModule(specifier, paths, '/');
};

// Follow member-access re-export chains and return { exp, uri, name } for the
// final definition, or null if name is not exported from uri at all.
// `visited` guards against circular re-export chains (A re-exports B re-exports A).
function _resolveExportFull(uri, name, visited) {
	if (!visited) visited = {};
	let key = uri + '\x00' + name;
	if (visited[key]) return null;
	visited[key] = true;
	let node = _nodes[uri];
	if (!node) return null;
	for (let i = 0; i < length(node.exports); i++) {
		let exp = node.exports[i];
		if (exp.name !== name) continue;
		if (!exp.memberRef && !exp.localRef) return { exp, uri, name };
		for (let j = 0; j < length(node.imports); j++) {
			let imp = node.imports[j];
			if (exp.memberRef) {
				if (!imp.resolvedUri || imp.alias !== exp.memberRef.alias) continue;
				return _resolveExportFull(imp.resolvedUri, exp.memberRef.member, visited) ?? { exp, uri, name };
			} else if (imp.alias === exp.localRef) {
				// namespace re-export: export const X = moduleAlias
				// Try to find an export named X in the module; fall back to a
				// synthetic module-typed entry so the type is never UNKNOWN.
				if (imp.resolvedUri) {
					let r = _resolveExportFull(imp.resolvedUri, name, visited);
					if (r) return r;
				}
				let synth = { name: exp.name, kind: 'const', doc: exp.doc,
				               _moduleSpecifier: imp.specifier,
				               memberRef: null, localRef: null, properties: null };
				return { exp: synth, uri, name };
			} else {
				// localRef: export const X = importedAlias (named import)
				if (!imp.resolvedUri || imp.alias || index(imp.symbols, exp.localRef) < 0) continue;
				let remoteName = (imp.renames && imp.renames[exp.localRef]) ?? exp.localRef;
				return _resolveExportFull(imp.resolvedUri, remoteName, visited) ?? { exp, uri, name };
			}
		}
		return { exp, uri, name };
	}
	return null;
}

// Return the resolved export entry, following member-access re-export chains.
export function resolveExport(uri, name) {
	let r = _resolveExportFull(uri, name);
	return r ? r.exp : null;
};

// Return { uri, name } for the final defining module after following chains.
// Falls back to the original { uri, name } when the export is not found or
// no chain exists.
export function resolveExportLocation(uri, name) {
	let r = _resolveExportFull(uri, name);
	return r ? { uri: r.uri, name: r.name } : { uri, name };
};

// Resolve a named member of a module specifier.
// Lazy-indexes the module from disk if not yet in the DAG, follows the full
// export chain, and returns { exp, uri, name } or null if not found.
// This is the single authoritative place for the "module type → member" lookup
// used by type inference, hover, and go-to-definition.
export function resolveMember(specifier, propName) {
	let modUri = resolveSpecifier(specifier);
	if (!modUri) return null;
	if (!_nodes[modUri]) addFromDisk(modUri);
	let loc = resolveExportLocation(modUri, propName);
	let exp = resolveExport(loc.uri, loc.name);
	return exp ? { exp, uri: loc.uri, name: loc.name } : null;
};
