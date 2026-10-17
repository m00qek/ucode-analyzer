import * as ts from 'tree_sitter';
import { eachName, declarationOf } from 'ucode_analyzer.code_analysis.bindings';
import { rangeOf } from 'ucode_analyzer.code_analysis.positions';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import { globalUri } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { matchPattern } from 'ucode_analyzer.code_analysis.glob';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';
import { toPath } from 'ucode_analyzer.code_analysis.uri';

// Names a runtime injects into a file's scope. LuCI runs controllers with its
// request environment as their scope and templates with that environment as
// their globals (luci/dispatcher.uc builds it; luci/runtime.uc adds to it);
// uhttpd gives its ucode handler (LuCI's uhttpd.uc) `uhttpd`.
// Installed: luci/…; in the luci tree: ucode/….
const LUCI_ENV = [
	'http', 'ubus', 'uci', 'ctx', 'version', 'config', 'dispatcher',
	'striptags', 'entityencode', '_', 'N_',
	'dispatched', 'requested', 'media', 'theme', 'resource', 'pkgs_update_time', 'include',
];
const PRESETS = [
	{ patterns: ['**/luci/controller/**', '**/ucode/controller/**',
	             '**/luci/template/**', '**/ucode/template/**'], names: LUCI_ENV },
	{ patterns: ['**/luci/uhttpd.uc', '**/ucode/uhttpd.uc'], names: ['uhttpd'] },
];

// Extra globals for the file at `uri`: the presets whose patterns match it,
// plus `workspace.globals` from the config — an array of names for every
// file, or { "<glob>": [names] } matched against the workspace-relative path.
function runtimeGlobals(uri) {
	let path = toPath(uri);
	let cfg = dag.config() ?? {};
	let ws = cfg.workspaceDir;
	let rel = (ws && substr(path, 0, length(ws) + 1) === ws + '/') ? substr(path, length(ws) + 1) : path;
	let out = [];
	for (let p in PRESETS)
		for (let pat in p.patterns)
			if (matchPattern(pat, rel)) { push(out, ...p.names); break; }
	let extra = cfg.workspace?.globals;
	if (type(extra) === 'array')
		push(out, ...extra);
	else if (type(extra) === 'object')
		for (let pat, names in extra)
			if (type(names) === 'array' && matchPattern(pat, rel)) push(out, ...names);
	return out;
}

export function undefinedVars(doc) {
	// Collect builtin names from the stdlib declaration module.
	// If the stdlib has not been initialized (tests, partial environments), skip
	// this check entirely to avoid a flood of false positives.
	let globals = {};
	let sUri = globalUri();
	if (!sUri) return [];

	if (!dag.exportsOf(sUri)) dag.addFromDisk(sUri);
	let exps = dag.exportsOf(sUri);
	if (!exps) return [];
	for (let i = 0; i < length(exps); i++) globals[exps[i].name] = true;
	for (let n in runtimeGlobals(doc.uri)) globals[n] = true;

	let source = doc.text;
	let diags  = [];
	eachName(ts.rootNode(doc.tree), source, {
		declare: () => null,
		use: (node, name, scope) => {
			if (declarationOf(scope, name) < 0 && !exists(globals, name))
				push(diags, diagnostic(rangeOf(source, doc.lineTable, node), Severity.WARNING, 'undefined-var',
					sprintf("'%s' is not defined", name)));
		},
	});
	return diags;
};
