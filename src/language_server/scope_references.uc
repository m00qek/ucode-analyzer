import * as ts from 'tree_sitter';

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
			if (ts.nodeType(param) === 'identifier')
				bind(scope, source, param, targetName, out);
		}
		return;
	}
}

// If block is the body of a for-in statement, bind the loop variable.
function bindForInVar(block, scope, source, targetName, out) {
	let parent = ts.parent(block);
	if (!parent || ts.nodeType(parent) !== 'for_in_statement') return;
	let left = ts.childByField(parent, 'left');
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
}

// If block is the body of a C-style for statement, bind its initializer.
function bindForVar(block, scope, source, targetName, out) {
	let parent = ts.parent(block);
	if (!parent || ts.nodeType(parent) !== 'for_statement') return;
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
	for (let i = 0; i < ts.namedChildCount(node); i++) {
		let clause = ts.namedChild(node, i);
		if (ts.nodeType(clause) !== 'import_clause') continue;
		for (let j = 0; j < ts.namedChildCount(clause); j++) {
			let part = ts.namedChild(clause, j);
			let pnt = ts.nodeType(part);
			if (pnt === 'namespace_import') {
				// import * as alias from '...'
				let aliasNode = ts.namedChild(part, 0);
				if (aliasNode) bind(scope, source, aliasNode, targetName, out);
			} else if (pnt === 'named_imports') {
				// import { x } or import { x as y }
				for (let k = 0; k < ts.namedChildCount(part); k++) {
					let spec = ts.namedChild(part, k);
					if (ts.nodeType(spec) !== 'import_specifier') continue;
					let count = ts.namedChildCount(spec);
					if (count === 0) continue;
					// For { remote as local }, local binding is the last child.
					// For { name }, first (and only) child is both remote and local.
					let localNode = ts.namedChild(spec, count - 1);
					if (localNode) bind(scope, source, localNode, targetName, out);
				}
			}
		}
	}
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
	if (nt === 'import_declaration') {
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
		let nameNode = ts.namedChild(node, 0);
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
		let inner = ts.namedChild(node, 0);
		if (inner) walk(inner, scope, source, targetName, out);
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

	// ── Statement block: new scope + implicit loop/catch bindings ───────────
	if (nt === 'statement_block') {
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
		let right = ts.childByField(node, 'right');
		if (right) walk(right, scope, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, targetName, out);
		return;
	}

	// ── C-style for: walk condition/increment in outer scope ────────────────
	// (The initializer binding is added by bindForVar when the body block is entered.)
	if (nt === 'for_statement') {
		let cond = ts.childByField(node, 'condition');
		if (cond) walk(cond, scope, source, targetName, out);
		let inc = ts.childByField(node, 'increment');
		if (inc) walk(inc, scope, source, targetName, out);
		let body = ts.childByField(node, 'body');
		if (body) walk(body, scope, source, targetName, out);
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

// Return all identifier nodes in the file that refer to the same binding as the
// identifier at cursorOffset.  Identifiers in different scopes that happen to
// share a name are excluded.
//
// Returns null if cursorOffset does not land on an identifier node.
// Returns an array (possibly empty) of tree-sitter node handles otherwise.
//
// The declaration node itself is included in the result; callers that want only
// use-sites (excluding the declaration) can filter out the first occurrence.
export function referencesOf(root, source, cursorOffset) {
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
		if (all[i].declOffset === anchor)
			push(result, all[i].node);
	}
	return result;
};
