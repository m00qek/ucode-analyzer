import * as ts from 'tree_sitter';
import { buildLineTable, rangeOf } from 'language_server.positions';

let SEVERITY_ERROR = 1;

// Scope: { decls: { name: 'const'|'let' }, parent }
function makeScope(parent) { return { decls: {}, parent }; }

function declKind(scope, name) {
	if (!scope) return null;
	if (exists(scope.decls, name)) return scope.decls[name];
	return declKind(scope.parent, name);
}

// Add formal parameter names to scope as 'let'-like bindings.
function addParams(node, source, scope) {
	let formalParams = ts.childByField(node, 'parameters');
	if (formalParams) {
		for (let i = 0; i < ts.namedChildCount(formalParams); i++) {
			let p = ts.namedChild(formalParams, i);
			if (ts.nodeType(p) === 'rest_element') {
				let inner = ts.namedChild(p, 0);
				if (inner && ts.nodeType(inner) === 'identifier')
					scope.decls[ts.text(inner, source)] = 'let';
			} else if (ts.nodeType(p) === 'identifier') {
				scope.decls[ts.text(p, source)] = 'let';
			}
		}
	} else {
		// Single-param arrow: parameter field
		let param = ts.childByField(node, 'parameter');
		if (param && ts.nodeType(param) === 'identifier')
			scope.decls[ts.text(param, source)] = 'let';
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
		let kw = ts.child(node, 0);
		let kind = (kw && ts.text(kw, source) === 'const') ? 'const' : 'let';
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let vd = ts.namedChild(node, i);
			if (ts.nodeType(vd) !== 'variable_declarator') continue;
			let nameNode = ts.childByField(vd, 'name');
			if (nameNode && ts.nodeType(nameNode) === 'identifier')
				scope.decls[ts.text(nameNode, source)] = kind;
			let val = ts.childByField(vd, 'value');
			if (val) _walk(val, scope, source, lineTable, diags);
		}
		return;
	}

	if (nt === 'function_declaration') {
		let nameNode = ts.namedChild(node, 0);
		if (nameNode && ts.nodeType(nameNode) === 'identifier')
			scope.decls[ts.text(nameNode, source)] = 'let';
		let inner = makeScope(scope);
		addParams(node, source, inner);
		let body = ts.childByField(node, 'body');
		if (body) _walkBlock(body, inner, source, lineTable, diags);
		return;
	}

	if (nt === 'export_statement') {
		let child = ts.namedChild(node, 0);
		if (child) _walk(child, scope, source, lineTable, diags);
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

	if (nt === 'statement_block') {
		_walkBlock(node, makeScope(scope), source, lineTable, diags);
		return;
	}

	if (nt === 'for_in_statement') {
		let inner = makeScope(scope);
		// for (let x in ...) — x is a new let binding, not const
		let left = ts.childByField(node, 'left');
		if (left && ts.nodeType(left) === 'identifier')
			inner.decls[ts.text(left, source)] = 'let';
		let right = ts.childByField(node, 'right');
		if (right) _walk(right, scope, source, lineTable, diags);
		let body = ts.childByField(node, 'body');
		if (body) _walk(body, inner, source, lineTable, diags);
		return;
	}

	if (nt === 'assignment_expression' || nt === 'augmented_assignment_expression') {
		let left = ts.namedChild(node, 0);
		if (left && ts.nodeType(left) === 'identifier') {
			let name = ts.text(left, source);
			if (declKind(scope, name) === 'const') {
				push(diags, {
					range:    rangeOf(source, lineTable, left),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'const-assignment',
					message:  sprintf("Cannot assign to '%s' — it is declared const", name),
				});
			}
		}
		let right = ts.namedChild(node, 1);
		if (right) _walk(right, scope, source, lineTable, diags);
		return;
	}

	if (nt === 'update_expression') {
		let operand = ts.namedChild(node, 0);
		if (operand && ts.nodeType(operand) === 'identifier') {
			let name = ts.text(operand, source);
			if (declKind(scope, name) === 'const') {
				push(diags, {
					range:    rangeOf(source, lineTable, operand),
					severity: SEVERITY_ERROR,
					source:   'ucode-ls',
					code:     'const-assignment',
					message:  sprintf("Cannot assign to '%s' — it is declared const", name),
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
	let lineTable = buildLineTable(source);
	let diags     = [];
	_walkBlock(root, makeScope(null), source, lineTable, diags);
	return diags;
};
