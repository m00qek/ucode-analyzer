import * as ts from 'tree_sitter';
import { offsetToPosition, buildLineTable } from 'language_server.positions';
import * as dag from 'language_server.dag.dag';
import { stdlibUri } from 'language_server.types.inferrer';

let SEVERITY_WARNING = 2;

function rangeOf(text, lineTable, node) {
	let start = offsetToPosition(text, lineTable, ts.startByte(node));
	let end   = offsetToPosition(text, lineTable, ts.endByte(node));
	return { start, end };
}

// ── Scope helpers ─────────────────────────────────────────────────────────────

function makeScope(parent) { return { names: {}, parent }; }

function scopeHas(scope, name) {
	let s = scope;
	while (s) {
		if (exists(s.names, name)) return true;
		s = s.parent;
	}
	return false;
}

function bind(scope, name) { scope.names[name] = true; }

// ── Parameter binding ────────────────────────────────────────────────────────

function bindParams(fnNode, scope, source) {
	for (let i = 0; i < ts.namedChildCount(fnNode); i++) {
		let child = ts.namedChild(fnNode, i);
		if (ts.nodeType(child) !== 'formal_parameters') continue;
		for (let j = 0; j < ts.namedChildCount(child); j++) {
			let p = ts.namedChild(child, j);
			if (ts.nodeType(p) === 'identifier') bind(scope, ts.text(p, source));
		}
		return;
	}
}

// ── For-in / for / catch variable binding ────────────────────────────────────

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

// ── Import binding ───────────────────────────────────────────────────────────

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

// ── AST walker ───────────────────────────────────────────────────────────────

function walk(node, scope, source, globals, lineTable, out) {
	let nt = ts.nodeType(node);

	// ── Identifier reference site ─────────────────────────────────────────────
	if (nt === 'identifier') {
		let name = ts.text(node, source);
		if (!scopeHas(scope, name) && !exists(globals, name))
			push(out, {
				range:    rangeOf(source, lineTable, node),
				severity: SEVERITY_WARNING,
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
				message:  sprintf("'%s' is not defined", name),
			});
		return;
	}

	// ── Import: bind local names, do not recurse (remote names are not refs) ──
	if (nt === 'import_statement') {
		bindImports(node, scope, source);
		return;
	}

	// ── Lexical declaration: bind name first, then walk initializer ───────────
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

	// ── Function declaration: name in outer scope, body in inner ─────────────
	if (nt === 'function_declaration') {
		let nameNode = ts.namedChild(node, 0);
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			bind(scope, ts.text(nameNode, source));
		let inner = makeScope(scope);
		bindParams(node, inner, source);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, globals, lineTable, out);
		return;
	}

	// ── Export statement: unwrap ───────────────────────────────────────────────
	if (nt === 'export_statement') {
		let inner = ts.namedChild(node, 0);
		if (inner) walk(inner, scope, source, globals, lineTable, out);
		return;
	}

	// ── Function expression / arrow: inner scope ───────────────────────────────
	if (nt === 'function_expression' || nt === 'arrow_function') {
		let inner = makeScope(scope);
		let first = ts.namedChild(node, 0);
		if (first && ts.nodeType(first) === 'formal_parameters') {
			// Regular parameter list.
			for (let i = 0; i < ts.namedChildCount(first); i++) {
				let p = ts.namedChild(first, i);
				if (ts.nodeType(p) === 'identifier') bind(inner, ts.text(p, source));
			}
		} else if (nt === 'arrow_function' && first && ts.nodeType(first) === 'identifier') {
			// Single-param arrow `x => expr` — bare identifier, no formal_parameters wrapper.
			bind(inner, ts.text(first, source));
		}
		let body = ts.childByField(node, 'body');
		if (body) {
			walk(body, inner, source, globals, lineTable, out);
		} else {
			// Fallback (expression body not reachable via childByField).
			// Walk every named child that is not the parameter node.
			let firstByte = first ? ts.startByte(first) : -1;
			for (let i = 0; i < ts.namedChildCount(node); i++) {
				let child = ts.namedChild(node, i);
				if (ts.startByte(child) !== firstByte)
					walk(child, inner, source, globals, lineTable, out);
			}
		}
		return;
	}

	// ── Catch clause: do NOT walk the parameter node (it is a declaration site).
	// The body statement_block will bind it via bindCatchVar. ──────────────────
	if (nt === 'catch_clause') {
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, globals, lineTable, out);
		return;
	}

	// ── Statement block: new scope + implicit loop/catch bindings ─────────────
	if (nt === 'statement_block') {
		let inner = makeScope(scope);
		bindForInVar(node, inner, source);
		bindForVar(node, inner, source);
		bindCatchVar(node, inner, source);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i), inner, source, globals, lineTable, out);
		return;
	}

	// ── For-in: walk iterable in current scope, body handles binding ──────────
	if (nt === 'for_in_statement') {
		let right = ts.childByField(node, 'right');
		if (right) walk(right, scope, source, globals, lineTable, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, globals, lineTable, out);
		return;
	}

	// ── C-style for: condition/increment in outer scope ───────────────────────
	if (nt === 'for_statement') {
		let cond = ts.childByField(node, 'condition');
		if (cond) walk(cond, scope, source, globals, lineTable, out);
		let inc = ts.childByField(node, 'increment');
		if (inc) walk(inc, scope, source, globals, lineTable, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, globals, lineTable, out);
		return;
	}

	// ── Member expression: only walk the object, not the property name ─────────
	if (nt === 'member_expression') {
		let obj = ts.childByField(node, 'object');
		if (obj) walk(obj, scope, source, globals, lineTable, out);
		return;
	}

	// ── Default: recurse into named children ────────────────────────────────────
	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), scope, source, globals, lineTable, out);
}

// ── Public API ────────────────────────────────────────────────────────────────

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
