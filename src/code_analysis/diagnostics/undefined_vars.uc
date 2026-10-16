import * as ts from 'tree_sitter';
import { firstNamed, namedNonComments } from 'code_analysis.ast_text';
import * as mode from 'code_analysis.mode';
import { rangeOf } from 'code_analysis.positions';
import * as dag from 'code_analysis.dag.dag';
import { globalUri } from 'code_analysis.types.dag_bridge';
import { makeScope, scopeHas, scopeSet } from 'code_analysis.types.scope';
import { matchPattern } from 'code_analysis.glob';

let SEVERITY_WARNING = 2;

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
	let path = substr(uri, 7);   // strip "file://"
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

function bind(scope, name) { scopeSet(scope, name, true); }

// Bind all identifier parameters from a formal_parameters node into scope.
function bindFormalParams(paramsNode, scope, source) {
	for (let i = 0; i < ts.namedChildCount(paramsNode); i++) {
		let p = ts.namedChild(paramsNode, i);
		if (ts.nodeType(p) === 'identifier') {
			bind(scope, ts.text(p, source));
		} else if (ts.nodeType(p) === 'rest_element') {
			let inner = firstNamed(p);
			if (inner && ts.nodeType(inner) === 'identifier')
				bind(scope, ts.text(inner, source));
		}
	}
}


function bindForInVar(block, scope, source) {
	let parent = ts.parent(block);
	if (!parent || (ts.nodeType(parent) !== 'for_in_statement' &&
	                ts.nodeType(parent) !== 'for_in_alt_statement')) return;
	let left = ts.childByField(parent, 'variable') ?? ts.childByField(parent, 'key');
	if (!left) return;
	if (ts.nodeType(left) === 'identifier') {
		bind(scope, ts.text(left, source));
	} else if (ts.nodeType(left) === 'lexical_declaration') {
		for (let i = 0; i < ts.namedChildCount(left); i++) {
			let vd = ts.namedChild(left, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nm = ts.childByField(vd, 'name');
			if (nm) bind(scope, ts.text(nm, source));
		}
	}
	// Bind the optional value variable in `for (let k, v in obj)`.
	let value = ts.childByField(parent, 'value');
	if (value && ts.nodeType(value) === 'identifier') bind(scope, ts.text(value, source));
}

function bindForVar(block, scope, source) {
	let parent = ts.parent(block);
	if (!parent || (ts.nodeType(parent) !== 'for_statement' &&
	                ts.nodeType(parent) !== 'for_alt_statement')) return;
	let init = ts.childByField(parent, 'initializer');
	if (!init || ts.nodeType(init) !== 'lexical_declaration') return;
	for (let i = 0; i < ts.namedChildCount(init); i++) {
		let vd = ts.namedChild(init, i);
		if (ts.nodeType(vd) !== 'variable_declarator') continue;
		let nm = ts.childByField(vd, 'name');
		if (nm) bind(scope, ts.text(nm, source));
	}
}

function bindCatchVar(block, scope, source) {
	let parent = ts.parent(block);
	if (!parent || ts.nodeType(parent) !== 'catch_clause') return;
	let param = ts.childByField(parent, 'parameter');
	if (param && ts.nodeType(param) === 'identifier') bind(scope, ts.text(param, source));
}


function bindImports(node, scope, source) {
	for (let n in mode.importBindingNodes(node))
		bind(scope, ts.text(n, source));
}


function walk(node, scope, source, globals, lineTable, out) {
	let nt = ts.nodeType(node);

	if (nt === 'identifier') {
		let name = ts.text(node, source);
		if (!scopeHas(scope, name) && !exists(globals, name))
			push(out, {
				range:    rangeOf(source, lineTable, node),
				severity: SEVERITY_WARNING,
				source:   'ucode-ls',
				code:     'undefined-var',
				message:  sprintf("'%s' is not defined", name),
			});
		return;
	}

	// Shorthand property { x } — x is a variable reference.
	if (nt === 'shorthand_property_identifier') {
		let name = ts.text(node, source);
		if (!scopeHas(scope, name) && !exists(globals, name))
			push(out, {
				range:    rangeOf(source, lineTable, node),
				severity: SEVERITY_WARNING,
				source:   'ucode-ls',
				code:     'undefined-var',
				message:  sprintf("'%s' is not defined", name),
			});
		return;
	}

	if (nt === 'import_statement') {
		bindImports(node, scope, source);
		return;
	}

	if (nt === 'lexical_declaration') {
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode) bind(scope, ts.text(nameNode, source));
			let val = ts.childByField(vd, 'value');
			if (val) walk(val, scope, source, globals, lineTable, out);
		}
		return;
	}

	if (nt === 'function_declaration') {
		let nameNode = ts.childByField(node, 'name');
		if (nameNode) bind(scope, ts.text(nameNode, source));
		let inner = makeScope(scope);
		let params = ts.childByField(node, 'parameters');
		if (params) bindFormalParams(params, inner, source);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, globals, lineTable, out);
		return;
	}

	if (nt === 'export_statement') {
		for (let inner in namedNonComments(node)) walk(inner, scope, source, globals, lineTable, out);
		return;
	}

	// Only the `name` field is a variable reference; `alias` is the exported name.
	if (nt === 'export_specifier') {
		let nameNode = ts.childByField(node, 'name');
		if (nameNode) walk(nameNode, scope, source, globals, lineTable, out);
		return;
	}

	if (nt === 'function_expression' || nt === 'arrow_function') {
		let inner = makeScope(scope);
		// Named function_expression: bind its own name so recursive calls inside don't warn.
		if (nt === 'function_expression') {
			let nameNode = ts.childByField(node, 'name');
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				bind(inner, ts.text(nameNode, source));
		}
		// Field access: `parameters` → formal_parameters for multi-param (works for
		// named/anonymous function_expression). `parameter` → bare ident for `x => expr`.
		let params = ts.childByField(node, 'parameters');
		if (params) {
			bindFormalParams(params, inner, source);
		} else {
			let param = ts.childByField(node, 'parameter');
			if (param && ts.nodeType(param) === 'identifier') bind(inner, ts.text(param, source));
		}
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, globals, lineTable, out);
		return;
	}

	// Do not walk the catch parameter — it is a declaration site, not a ref.
	if (nt === 'catch_clause') {
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, globals, lineTable, out);
		return;
	}

	// A brace block, or the statement_list of an alt-syntax body.
	if (nt === 'statement_block' || nt === 'statement_list') {
		let inner = makeScope(scope);
		bindForInVar(node, inner, source);
		bindForVar(node, inner, source);
		bindCatchVar(node, inner, source);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i), inner, source, globals, lineTable, out);
		return;
	}

	if (nt === 'for_in_statement' || nt === 'for_in_alt_statement') {
		let right = ts.childByField(node, 'object');
		if (right) walk(right, scope, source, globals, lineTable, out);
		let body = ts.childByField(node, 'body');
		if (body) {
			let bt = ts.nodeType(body);
			if (bt === 'statement_block' || bt === 'statement_list') {
				// The block handler calls bindForInVar automatically.
				walk(body, scope, source, globals, lineTable, out);
			} else {
				// No-brace body: bind loop var into an explicit inner scope.
				let inner = makeScope(scope);
				bindForInVar(body, inner, source);
				walk(body, inner, source, globals, lineTable, out);
			}
		}
		return;
	}

	if (nt === 'for_statement' || nt === 'for_alt_statement') {
		// Bind the loop vars into an inner scope so condition/increment can
		// reference them. Each initializer sees the declarators before it
		// (`for (let i = 0, x = xs[i]; …)`).
		let inner = makeScope(scope);
		let init = ts.childByField(node, 'initializer');
		if (init && ts.nodeType(init) === 'lexical_declaration') {
			for (let vd in ts.namedChildren(init)) {
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let val = ts.childByField(vd, 'value');
				if (val) walk(val, inner, source, globals, lineTable, out);
				let nm = ts.childByField(vd, 'name');
				if (nm && ts.nodeType(nm) === 'identifier') bind(inner, ts.text(nm, source));
			}
		} else if (init) {
			walk(init, scope, source, globals, lineTable, out);
		}
		let cond = ts.childByField(node, 'condition');
		if (cond) walk(cond, inner, source, globals, lineTable, out);
		let inc = ts.childByField(node, 'increment');
		if (inc) walk(inc, inner, source, globals, lineTable, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, globals, lineTable, out);
		return;
	}

	// Property name is not a variable reference; only the object side is.
	if (nt === 'member_expression') {
		let obj = ts.childByField(node, 'object');
		if (obj) walk(obj, scope, source, globals, lineTable, out);
		return;
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), scope, source, globals, lineTable, out);
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

	let source    = doc.text;
	let lineTable = doc.lineTable;
	let diags     = [];
	walk(ts.rootNode(doc.tree), makeScope(null), source, globals, lineTable, diags);
	return diags;
};
