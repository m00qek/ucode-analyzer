import * as ts from 'tree_sitter';
import { firstNamed, namedNonComments } from 'code_analysis.ast_text';
import * as mode from 'code_analysis.mode';

// Lightweight scope used only for tracking declaration byte-offsets.
// Separate from the type-inference scope so this module has no dependency on
// the inferrer, and the walk stays fast (no JSDoc parsing or type-building).
//
// bindings: { name: startByte_of_declaring_identifier }
// Unresolved names (not declared in any enclosing scope) get declOffset -1.
function makeScope(parent) {
	return { bindings: {}, parent };
}

function resolve(scope, name) {
	let s = scope;
	while (s) {
		if (exists(s.bindings, name)) return s.bindings[name];
		s = s.parent;
	}
	return -1;
}

// Bind a single identifier node as a declaration in scope.
// Also pushes the node to `out` when its name matches targetName, so that
// declaration sites appear in results alongside reference sites.
function bind(scope, source, nameNode, targetName, out) {
	let nm = ts.text(nameNode, source);
	let declOffset = ts.startByte(nameNode);
	scope.bindings[nm] = declOffset;
	if (nm === targetName)
		push(out, { node: nameNode, declOffset });
}

// Add formal parameters of a function/arrow node to scope, collecting
// any parameter identifier whose name matches targetName into out.
function collectParams(fnNode, scope, source, targetName, out) {
	for (let i = 0; i < ts.namedChildCount(fnNode); i++) {
		let child = ts.namedChild(fnNode, i);
		if (ts.nodeType(child) !== 'formal_parameters') continue;
		for (let j = 0; j < ts.namedChildCount(child); j++) {
			let param = ts.namedChild(child, j);
			let pnt = ts.nodeType(param);
			if (pnt === 'identifier') {
				bind(scope, source, param, targetName, out);
			} else if (pnt === 'rest_element') {
				let inner = firstNamed(param);
				if (inner && ts.nodeType(inner) === 'identifier')
					bind(scope, source, inner, targetName, out);
			}
		}
		return;
	}
}

// If block is the body of a for-in statement, bind the loop variable.
function bindForInVar(block, scope, source, targetName, out) {
	let parent = ts.parent(block);
	if (!parent || (ts.nodeType(parent) !== 'for_in_statement' &&
	                ts.nodeType(parent) !== 'for_in_alt_statement')) return;
	let left = ts.childByField(parent, 'variable') ?? ts.childByField(parent, 'key');
	if (!left) return;
	if (ts.nodeType(left) === 'identifier') {
		// for (x in arr) — bare identifier (re-use of existing variable)
		bind(scope, source, left, targetName, out);
	} else if (ts.nodeType(left) === 'lexical_declaration') {
		for (let i = 0; i < ts.namedChildCount(left); i++) {
			let vd = ts.namedChild(left, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode) bind(scope, source, nameNode, targetName, out);
		}
	}
	// Bind the optional value variable in `for (let k, v in obj)`.
	let value = ts.childByField(parent, 'value');
	if (value && ts.nodeType(value) === 'identifier')
		bind(scope, source, value, targetName, out);
}

// If block is the body of a C-style for statement, bind its initializer.
function bindForVar(block, scope, source, targetName, out) {
	let parent = ts.parent(block);
	if (!parent || (ts.nodeType(parent) !== 'for_statement' &&
	                ts.nodeType(parent) !== 'for_alt_statement')) return;
	let init = ts.childByField(parent, 'initializer');
	if (!init || ts.nodeType(init) !== 'lexical_declaration') return;
	for (let i = 0; i < ts.namedChildCount(init); i++) {
		let vd = ts.namedChild(init, i);
		if (ts.nodeType(vd) !== 'variable_declarator') continue;
		let nameNode = ts.childByField(vd, 'name');
		if (nameNode) bind(scope, source, nameNode, targetName, out);
	}
}

// If block is the body of a catch clause, bind the catch parameter.
function bindCatchVar(block, scope, source, targetName, out) {
	let parent = ts.parent(block);
	if (!parent || ts.nodeType(parent) !== 'catch_clause') return;
	let param = ts.childByField(parent, 'parameter');
	if (param && ts.nodeType(param) === 'identifier')
		bind(scope, source, param, targetName, out);
}

// Register local bindings from an import_declaration into scope.
// Never recurses into the declaration (import specifiers are not reference sites).
function bindImports(node, scope, source, targetName, out) {
	for (let n in mode.importBindingNodes(node))
		bind(scope, source, n, targetName, out);
}

// Walk `node` maintaining `scope`.
// For every identifier node named `targetName` — whether a declaration site or a
// reference site — push { node, declOffset } to `out`.
// Declaration nodes are handled explicitly so their name identifiers are bound in
// scope at the right point (no hoisting) and also counted as occurrences.
function walk(node, scope, source, targetName, out) {
	let nt = ts.nodeType(node);

	// ── Reference site ─────────────────────────────────────────────────────
	if (nt === 'identifier') {
		if (ts.text(node, source) === targetName)
			push(out, { node, declOffset: resolve(scope, targetName) });
		return;
	}

	// ── Import: bind locals only, no recursive walk into specifiers ─────────
	if (nt === 'import_statement') {
		bindImports(node, scope, source, targetName, out);
		return;
	}

	// ── Lexical declaration: bind name, then walk the initializer ───────────
	if (nt === 'lexical_declaration') {
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode) bind(scope, source, nameNode, targetName, out);
			let val = ts.childByField(vd, 'value');
			if (val) walk(val, scope, source, targetName, out);
		}
		return;
	}

	// ── Function declaration: name in outer scope, body in inner scope ──────
	if (nt === 'function_declaration') {
		let nameNode = ts.childByField(node, 'name');
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			bind(scope, source, nameNode, targetName, out);
		let inner = makeScope(scope);
		collectParams(node, inner, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, targetName, out);
		return;
	}

	// ── Export statement: delegate to the wrapped declaration ───────────────
	if (nt === 'export_statement') {
		for (let inner in namedNonComments(node)) walk(inner, scope, source, targetName, out);
		return;
	}

	// ── Function expression / arrow: params in inner scope ──────────────────
	if (nt === 'function_expression' || nt === 'arrow_function') {
		let inner = makeScope(scope);
		collectParams(node, inner, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) {
			walk(body, inner, source, targetName, out);
		} else {
			// Arrow with expression body (no statement_block): walk all non-param children.
			for (let i = 0; i < ts.namedChildCount(node); i++) {
				let child = ts.namedChild(node, i);
				if (ts.nodeType(child) !== 'formal_parameters')
					walk(child, inner, source, targetName, out);
			}
		}
		return;
	}

	// ── Statement block (or an alt-syntax body's statement_list): new scope
	//    + implicit loop/catch bindings ───────────────────────────────────────
	if (nt === 'statement_block' || nt === 'statement_list') {
		let inner = makeScope(scope);
		bindForInVar(node, inner, source, targetName, out);
		bindForVar(node, inner, source, targetName, out);
		bindCatchVar(node, inner, source, targetName, out);
		for (let i = 0; i < ts.namedChildCount(node); i++)
			walk(ts.namedChild(node, i), inner, source, targetName, out);
		return;
	}

	// ── For-in: walk iterable in current scope, body handles the binding ────
	if (nt === 'for_in_statement') {
		let right = ts.childByField(node, 'object');
		if (right) walk(right, scope, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) {
			if (ts.nodeType(body) === 'statement_block') {
				// statement_block handler calls bindForInVar automatically.
				walk(body, scope, source, targetName, out);
			} else {
				// No-brace body: bind loop var into an explicit inner scope.
				let inner = makeScope(scope);
				bindForInVar(body, inner, source, targetName, out);
				walk(body, inner, source, targetName, out);
			}
		}
		return;
	}

	// ── C-style for: bind initializer in inner scope so condition/increment
	// can resolve the loop variable. bindForVar pushes the declaration to `out`
	// when the body block is entered — we only pre-bind here, without pushing.
	if (nt === 'for_statement') {
		let inner = makeScope(scope);
		let init = ts.childByField(node, 'initializer');
		if (init && ts.nodeType(init) === 'lexical_declaration') {
			for (let i = 0; i < ts.namedChildCount(init); i++) {
				let vd = ts.namedChild(init, i);
				if (ts.nodeType(vd) !== 'variable_declarator') continue;
				let val = ts.childByField(vd, 'value');
				if (val) walk(val, scope, source, targetName, out);
				let nm = ts.childByField(vd, 'name');
				if (nm && ts.nodeType(nm) === 'identifier')
					inner.bindings[ts.text(nm, source)] = ts.startByte(nm);
			}
		} else if (init) {
			walk(init, scope, source, targetName, out);
		}
		let cond = ts.childByField(node, 'condition');
		if (cond) walk(cond, inner, source, targetName, out);
		let inc = ts.childByField(node, 'increment');
		if (inc) walk(inc, inner, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, inner, source, targetName, out);
		return;
	}

	// ── Default: recurse into named children ─────────────────────────────────
	for (let i = 0; i < ts.namedChildCount(node); i++)
		walk(ts.namedChild(node, i), scope, source, targetName, out);
}

// Find the deepest identifier node whose byte span contains offset, or null.
function identifierAt(node, offset) {
	if (ts.startByte(node) > offset || offset >= ts.endByte(node)) return null;
	let result = (ts.nodeType(node) === 'identifier') ? node : null;
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let deeper = identifierAt(ts.namedChild(node, i), offset);
		if (deeper) result = deeper;
	}
	return result;
}

// Return the anchor (declaration site) information for the identifier at
// cursorOffset, or null if the offset does not land on an identifier.
// { targetName, anchorByte, anchorNode }:
//   anchorByte  — declaration byte-offset (-1 when the name is unresolved/global)
//   anchorNode  — the identifier ts-node at anchorByte, or null
export function anchorOf(root, source, cursorOffset) {
	let cursorNode = identifierAt(root, cursorOffset);
	if (!cursorNode) return null;
	let targetName = ts.text(cursorNode, source);
	let cursorStart = ts.startByte(cursorNode);
	let all = [];
	walk(root, makeScope(null), source, targetName, all);
	for (let i = 0; i < length(all); i++) {
		if (ts.startByte(all[i].node) === cursorStart) {
			let anchorByte = all[i].declOffset;
			let anchorNode = (anchorByte >= 0) ? identifierAt(root, anchorByte) : null;
			return { targetName, anchorByte, anchorNode };
		}
	}
	return null;
};

// Return all identifier nodes in the file that refer to the same binding as the
// identifier at cursorOffset.  Identifiers in different scopes that happen to
// share a name are excluded.
//
// Returns null if cursorOffset does not land on an identifier node.
// Returns an array (possibly empty) of tree-sitter node handles otherwise.
//
// When includeDeclaration is false, the declaration site node (startByte ===
// declOffset) is excluded from the result.  Defaults to true (LSP spec: the
// client must opt out explicitly via context.includeDeclaration = false).
export function referencesOf(root, source, cursorOffset, includeDeclaration) {
	let cursorNode = identifierAt(root, cursorOffset);
	if (!cursorNode) return null;

	let targetName = ts.text(cursorNode, source);
	let cursorStart = ts.startByte(cursorNode);

	// Collect all occurrences of targetName with their resolved declaration offset.
	let all = [];
	walk(root, makeScope(null), source, targetName, all);

	// Determine the anchor: which declaration does the cursor identifier resolve to?
	// anchor = -2 means the cursor node was not found in walk results (should not happen).
	let anchor = -2;
	for (let i = 0; i < length(all); i++) {
		if (ts.startByte(all[i].node) === cursorStart) {
			anchor = all[i].declOffset;
			break;
		}
	}
	if (anchor === -2) return null;

	// Return only occurrences that share the same anchor.
	let result = [];
	for (let i = 0; i < length(all); i++) {
		if (all[i].declOffset !== anchor) continue;
		if (includeDeclaration === false && ts.startByte(all[i].node) === anchor) continue;
		push(result, all[i].node);
	}
	return result;
};
