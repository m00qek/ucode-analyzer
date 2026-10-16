import * as ts from 'tree_sitter';
import { firstNamed, namedNonComments } from 'code_analysis.ast_text';
import { rangeOf } from 'code_analysis.positions';

let SEVERITY_ERROR = 1;

// Scope: { decls: { name: 'const'|'let' }, parent }
function makeScope(parent) { return { decls: {}, parent }; }

// Returns { kind: 'const'|'let', kwRange? } or null.
function declEntry(scope, name) {
	if (!scope) return null;
	if (exists(scope.decls, name)) return scope.decls[name];
	return declEntry(scope.parent, name);
}

// Add formal parameter names to scope as 'let'-like bindings.
function addParams(node, source, scope) {
	let formalParams = ts.childByField(node, 'parameters');
	if (formalParams) {
		for (let i = 0; i < ts.namedChildCount(formalParams); i++) {
			let p = ts.namedChild(formalParams, i);
			if (ts.nodeType(p) === 'rest_element') {
				let inner = firstNamed(p);
				if (inner && ts.nodeType(inner) === 'identifier')
					scope.decls[ts.text(inner, source)] = { kind: 'let' };
			} else if (ts.nodeType(p) === 'identifier') {
				scope.decls[ts.text(p, source)] = { kind: 'let' };
			}
		}
	} else {
		// Single-param arrow: parameter field
		let param = ts.childByField(node, 'parameter');
		if (param && ts.nodeType(param) === 'identifier')
			scope.decls[ts.text(param, source)] = { kind: 'let' };
	}
}

let _walk;
let _walkBlock;

_walkBlock = function(node, scope, source, lineTable, diags) {
	for (let i = 0; i < ts.namedChildCount(node); i++)
		_walk(ts.namedChild(node, i), scope, source, lineTable, diags);
};

_walk = function(node, scope, source, lineTable, diags) {
	if (!node) return;
	let nt = ts.nodeType(node);

	if (nt === 'import_statement') return;

	if (nt === 'lexical_declaration') {
		let kw   = ts.child(node, 0);
		let kind = (kw && ts.text(kw, source) === 'const') ? 'const' : 'let';
		let entry = kind === 'const'
			? { kind, kwRange: rangeOf(source, lineTable, kw) }
			: { kind };
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				scope.decls[ts.text(nameNode, source)] = entry;
			let val = ts.childByField(vd, 'value');
			if (val) _walk(val, scope, source, lineTable, diags);
		}
		return;
	}

	if (nt === 'function_declaration') {
		let nameNode = ts.childByField(node, 'name');
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			scope.decls[ts.text(nameNode, source)] = { kind: 'let' };
		let inner = makeScope(scope);
		addParams(node, source, inner);
		let body = ts.childByField(node, 'body');
		if (body) _walkBlock(body, inner, source, lineTable, diags);
		return;
	}

	if (nt === 'export_statement') {
		for (let child in namedNonComments(node)) _walk(child, scope, source, lineTable, diags);
		return;
	}

	if (nt === 'arrow_function' || nt === 'function_expression') {
		let inner = makeScope(scope);
		addParams(node, source, inner);
		let body = ts.childByField(node, 'body');
		if (body) {
			if (ts.nodeType(body) === 'statement_block')
				_walkBlock(body, inner, source, lineTable, diags);
			else
				_walk(body, inner, source, lineTable, diags);
		}
		return;
	}

	if (nt === 'statement_block' || nt === 'statement_list') {
		_walkBlock(node, makeScope(scope), source, lineTable, diags);
		return;
	}

	if (nt === 'for_in_statement') {
		let inner = makeScope(scope);
		// for (let x in ...) — x is a new let binding, not const
		let left = ts.childByField(node, 'variable') ?? ts.childByField(node, 'key');
		if (left && ts.nodeType(left) === 'identifier')
			inner.decls[ts.text(left, source)] = { kind: 'let' };
		let right = ts.childByField(node, 'object');
		if (right) _walk(right, scope, source, lineTable, diags);
		let body = ts.childByField(node, 'body');
		if (body) _walk(body, inner, source, lineTable, diags);
		return;
	}

	if (nt === 'assignment_expression' || nt === 'augmented_assignment_expression') {
		let left = ts.childByField(node, 'left');
		if (left && ts.nodeType(left) === 'identifier') {
			let name  = ts.text(left, source);
			let entry = declEntry(scope, name);
			if (entry?.kind === 'const') {
				push(diags, {
					range:    rangeOf(source, lineTable, left),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'const-assignment',
					message:  sprintf("Cannot assign to '%s' — it is declared const", name),
					data:     { constKeywordRange: entry.kwRange },
				});
			}
		}
		let right = ts.childByField(node, 'right');
		if (right) _walk(right, scope, source, lineTable, diags);
		return;
	}

	if (nt === 'update_expression') {
		let operand = ts.childByField(node, 'argument');
		if (operand && ts.nodeType(operand) === 'identifier') {
			let name  = ts.text(operand, source);
			let entry = declEntry(scope, name);
			if (entry?.kind === 'const') {
				push(diags, {
					range:    rangeOf(source, lineTable, operand),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'const-assignment',
					message:  sprintf("Cannot assign to '%s' — it is declared const", name),
					data:     { constKeywordRange: entry.kwRange },
				});
			}
		}
		return;
	}

	for (let i = 0; i < ts.namedChildCount(node); i++)
		_walk(ts.namedChild(node, i), scope, source, lineTable, diags);
};

export function assignmentToConst(doc) {
	let root      = ts.rootNode(doc.tree);
	let source    = doc.text;
	let lineTable = doc.lineTable;
	let diags     = [];
	_walkBlock(root, makeScope(null), source, lineTable, diags);
	return diags;
};
