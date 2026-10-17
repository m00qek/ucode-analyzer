import * as fs from 'fs';
import * as mode from 'ucode_analyzer.code_analysis.mode';
import { extractExports, extractImports, extractTypedefs, extractModuleDoc, extractVersions, resolveModule } from 'ucode_analyzer.code_analysis.dag.indexer';
import * as type_registry from 'ucode_analyzer.code_analysis.types.registry';
import { libraryDirs } from 'ucode_analyzer.code_analysis.config';
import { toPath } from 'ucode_analyzer.code_analysis.uri';

let _config = {};
let _nodes = {};
let _outEdges = {};
let _inEdges = {};
let _openUris = {};
// uri -> { mtime, size } captured the last time we indexed the file from disk.
// Lets the update cascade skip re-reading an on-disk dependent whose content is
// unchanged (the common case: editing one file cascades through dependents whose
// own text hasn't moved). Same per-uri lifecycle as _nodes.
let _diskStamp = {};

function resolvedLibPaths() {
	let out = libraryDirs(_config);
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
		// Once per imported file, however many statements import it.
		if (!imp.resolvedUri || index(targets, imp.resolvedUri) >= 0) continue;
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

// A value without its `position` keys, at any depth.
function withoutPositions(v) {
	if (type(v) === 'array') return map(v, withoutPositions);
	if (type(v) !== 'object') return v;
	let out = {};
	for (let k, x in v)
		if (k !== 'position') out[k] = withoutPositions(x);
	return out;
}

// What importers see of a file, as a comparable string. Export positions are
// left out: an edit above an export moves them, and importers read them from
// the DAG when they need them rather than keeping copies.
function interfaceOf(uri) {
	let node = _nodes[uri];
	if (!node) return null;
	return sprintf('%J', [withoutPositions(node.exports), node.imports, node.moduleDoc,
		node.versions, type_registry.definedIn(uri)]);
}

function readAndParse(path) {
	let text = fs.readfile(path);
	return (text === null) ? null : { text, tree: mode.parse(text) };
}

export function init(config) {
	_config = config;
	_openUris = {};
};

// The configuration passed to init().
export function config() {
	return _config;
};

export function markOpen(uri) { _openUris[uri] = true; };
export function markClosed(uri) { delete _openUris[uri]; };

// Index with provided content (no cascade — used for initial workspace scan).
export function add(uri, text, tree) {
	indexNode(uri, text, tree);
};

// Index a file from disk (no cascade — used for initial workspace scan).
export function addFromDisk(uri) {
	let path = toPath(uri);
	let parsed = readAndParse(path);
	if (parsed) {
		indexNode(uri, parsed.text, parsed.tree);
		let st = fs.stat(path);
		if (st) _diskStamp[uri] = { mtime: st.mtime, size: st.size };
	}
};

// Re-index a file with the given content, then cascade through reverse deps.
// openDocs is an optional map of uri -> {text, tree} for currently open files;
// when provided, open dependents are re-indexed from memory instead of skipped.
// Returns the list of dependent URIs that were re-indexed (excluding uri itself):
// none when the file's interface is unchanged (an edit inside a function body,
// a comment), since nothing an importer sees has moved.
export function update(uri, text, tree, openDocs) {
	let before = interfaceOf(uri);
	indexNode(uri, text, tree);
	if (before !== null && interfaceOf(uri) === before)
		return [];

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
			let path = toPath(next);
			let stamp = _diskStamp[next];
			let st = stamp ? fs.stat(path) : null;
			if (stamp && st && st.mtime === stamp.mtime && st.size === stamp.size) {
				// Unchanged on disk since we last indexed it. Re-indexing derives
				// the node purely from this file's own (unmoved) text, so it would
				// be a no-op — skip the read+parse. Genuine on-disk edits arrive
				// via watched-files/didChange and bump mtime/size; open edits take
				// the _openUris branch. Still traverse its reverse deps below.
			} else {
				let parsed = readAndParse(path);
				if (parsed) {
					indexNode(next, parsed.text, parsed.tree);
					let s2 = st ?? fs.stat(path);
					if (s2) _diskStamp[next] = { mtime: s2.mtime, size: s2.size };
				} else {
					// File no longer on disk — cascade its reverse deps then remove it.
					let revDeps = _inEdges[next] ?? [];
					removeOutEdges(next);
					delete _nodes[next];
					delete _inEdges[next];
					delete _openUris[next];
					delete _diskStamp[next];
					type_registry.removeUri(next);
					for (let dep in revDeps)
						if (!visited[dep]) { visited[dep] = true; push(queue, dep); }
					continue;
				}
			}
		}

		for (let dep in (_inEdges[next] ?? []))
			if (!visited[dep]) { visited[dep] = true; push(queue, dep); }
	}

	return queue;
};

// Resolve the imports of `uris` again, after a file appeared or disappeared
// on disk, and rewire their edges. Returns those whose resolution changed.
function reresolve(uris) {
	let changed = [];
	for (let uri in uris) {
		let node = _nodes[uri];
		if (!node) continue;
		let before = sprintf('%J', map(node.imports, (i) => i.resolvedUri));
		resolveAll(node.imports);
		if (sprintf('%J', map(node.imports, (i) => i.resolvedUri)) === before) continue;
		removeOutEdges(uri);
		addOutEdges(uri, node.imports);
		push(changed, uri);
	}
	return changed;
}

// Forget a file. Its importers resolve their imports again: the specifier may
// now name another file (a declaration stub), or nothing.
export function remove(uri) {
	let importers = _inEdges[uri] ?? [];
	removeOutEdges(uri);
	delete _nodes[uri];
	delete _inEdges[uri];
	delete _openUris[uri];
	delete _diskStamp[uri];
	type_registry.removeUri(uri);
	reresolve(importers);
};

// Resolve again every import that resolved to nothing, as a new file on disk
// may now satisfy it. Returns the files whose imports changed.
export function resolveUnresolved() {
	let pending = [];
	for (let uri, node in _nodes)
		for (let imp in node.imports)
			if (!imp.resolvedUri) { push(pending, uri); break; }
	return reresolve(pending);
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

// The specifier that imports `uri` (`luci.http` for <lib>/luci/http.uc,
// `fs` for <self>/declarations/fs.d.uc), or null: the shortest one that
// resolves back to `uri` from some library path.
export function specifierOf(uri) {
	let path = toPath(uri);
	let best = null;
	for (let lib in resolvedLibPaths()) {
		if (substr(path, 0, length(lib) + 1) !== lib + '/') continue;
		let rel = substr(path, length(lib) + 1);
		let decl = (substr(rel, -5) === '.d.uc');
		rel = substr(rel, 0, length(rel) - (decl ? 5 : 3));
		if (decl && substr(rel, 0, 13) === 'declarations/') rel = substr(rel, 13);
		let spec = replace(rel, /\//g, '.');
		if (resolveSpecifier(spec) === uri && (best === null || length(spec) < length(best))) best = spec;
	}
	return best;
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
