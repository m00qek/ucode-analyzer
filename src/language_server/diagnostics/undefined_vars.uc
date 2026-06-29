import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';
import * as dag from 'language_server.dag.dag';
import { stdlibUri } from 'language_server.types.inferrer';
import { makeScope, scopeHas, scopeSet } from 'language_server.types.scope';

let SEVERITY_WARNING = 2;

function bind(scope, name) { scopeSet(scope, name, true); }

// Bind all identifier parameters from a formal_parameters node into scope.
function bindFormalParams(paramsNode, scope, source) {
	for (let i = 0; i < ts.namedChildCount(paramsNode); i++) {
		let p = ts.namedChild(paramsNode, i);
		if (ts.nodeType(p) === 'identifier') {
			bind(scope, ts.text(p, source));
		} else if (ts.nodeType(p) === 'rest_element') {
			let inner = ts.namedChild(p, 0);
			if (inner && ts.nodeType(inner) === 'identifier')
				bind(scope, ts.text(inner, source));
		}
	}
}


function bindForInVar(block, scope, source) {
	let parent = ts.parent(block);
	if (!parent || ts.nodeType(parent) !== 'for_in_statement') return;
	let left = ts.childByField(parent, 'left');
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
	if (!parent || ts.nodeType(parent) !== 'for_statement') return;
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
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let clause = ts.namedChild(node, i);
		if (ts.nodeType(clause) !== 'import_clause') continue;
		for (let j = 0; j < ts.namedChildCount(clause); j++) {
			let part = ts.namedChild(clause, j);
			let pnt = ts.nodeType(part);
			if (pnt === 'namespace_import') {
				let alias = ts.namedChild(part, 0);
				if (alias) bind(scope, ts.text(alias, source));
			} else if (pnt === 'named_imports') {
				for (let k = 0; k < ts.namedChildCount(part); k++) {
					let spec = ts.namedChild(part, k);
					if (ts.nodeType(spec) !== 'import_specifier') continue;
					let count = ts.namedChildCount(spec);
					if (count === 0) continue;
					let localNode = ts.namedChild(spec, count - 1);
					if (localNode) bind(scope, ts.text(localNode, source));
				}
			}
		}
	}
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
		let inner = ts.namedChild(node, 0);
		if (inner) walk(inner, scope, source, globals, lineTable, out);
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

	if (nt === 'statement_block') {
		let inner = makeScope(scope);
		bindForInVar(node, inner, source);
		bindForVar(node, inner, source);
		bindCatchVar(node, inner, source);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i), inner, source, globals, lineTable, out);
		return;
	}

	if (nt === 'for_in_statement') {
		let right = ts.childByField(node, 'right');
		if (right) walk(right, scope, source, globals, lineTable, out);
		let body = ts.childByField(node, 'body');
		if (body) {
			if (ts.nodeType(body) === 'statement_block') {
				// statement_block handler calls bindForInVar automatically.
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

	if (nt === 'for_statement') {
		// Walk initializer RHS in outer scope first, then bind the loop var into an
		// inner scope so condition/increment can reference it without false positives.
		let inner = makeScope(scope);
		let init = ts.childByField(node, 'initializer');
		if (init && ts.nodeType(init) === 'lexical_declaration') {
			for (let i = 0; i < ts.namedChildCount(init); i++) {
				let vd = ts.namedChild(init, i);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let val = ts.childByField(vd, 'value');
				if (val) walk(val, scope, source, globals, lineTable, out);
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
	let sUri = stdlibUri();
	if (!sUri) return [];

	if (!dag.exportsOf(sUri)) dag.addFromDisk(sUri);
	let exps = dag.exportsOf(sUri);
	if (!exps) return [];
	for (let i = 0; i < length(exps); i++) globals[exps[i].name] = true;

	let source    = doc.text;
	let lineTable = buildLineTable(source);
	let diags     = [];
	walk(ts.rootNode(doc.tree), makeScope(null), source, globals, lineTable, diags);
	return diags;
};
