import * as ts from 'tree_sitter';

let _parser = ts.newParser(ts.ucdocs());

// ── Description text ──────────────────────────────────────────────────────

// The ucdocs extras rule silently consumes \n[ \t]*\** [ \t]* between tokens,
// but ts.text() returns raw byte spans, so those sequences appear in
// description node text. Strip the JSDoc line prefix (" * ") but preserve
// any additional indentation that follows it (e.g. in @example code blocks).
function cleanDesc(text) {
	text = replace(text, /\n[ \t]*\*?[ \t]?/g, '\n');
	text = replace(text, /^\s+/, '');
	text = replace(text, /\s+$/, '');
	return text;
}

function descText(node, source) {
	return node ? cleanDesc(ts.text(node, source)) : null;
}

// ── Type parsing ──────────────────────────────────────────────────────────

// Builtin names the ucdocs grammar lexes as primitive_type that this type system
// has no primitive for (ucode's runtime names, plus `number`). Earlier grammars
// parsed them as named_type references; keep producing exactly those opaque refs
// so typing is unchanged. (Mapping them — number → int|float, object → dict,
// array → list — would be a deliberate type-system change, not a port.)
const OPAQUE_BUILTINS = {
	integer: true, double: true, number: true,
	object: true, array: true, regexp: true, resource: true,
};

// Declared first: ucode cannot refer to a `let` from its own initializer, and
// parseTypeNode is recursive.
let parseTypeNode;

parseTypeNode = function(node, source, tparams) {
	let kind = ts.nodeType(node);

	if (kind === 'primitive_type') {
		let name = ts.text(node, source);
		// A bare `{function}` annotation means "some callable" — model it as an
		// opaque function type so call sites don't flag it as not-a-function.
		// (`{function(): T}` with a signature is handled by function_type below.)
		if (name === 'function')
			return { kind: 'function', params: [], return: { kind: 'unknown' } };
		if (OPAQUE_BUILTINS[name])
			return { kind: 'ref', name, params: [] };
		return { kind: 'primitive', name };
	}

	if (kind === 'any_type')
		return { kind: 'any' };

	if (kind === 'list_type') {
		let elem = ts.childByField(node, 'element');
		return { kind: 'generic', base: 'list', params: [elem ? parseTypeNode(elem, source, tparams) : { kind: 'unknown' }] };
	}

	if (kind === 'dict_type') {
		let val = ts.childByField(node, 'value');
		return { kind: 'generic', base: 'dict', params: [val ? parseTypeNode(val, source, tparams) : { kind: 'unknown' }] };
	}

	if (kind === 'record_type') {
		let fields = [];
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let f = ts.namedChild(node, i);
			if (ts.nodeType(f) !== 'record_field') continue;
			push(fields, {
				name: ts.text(ts.namedChild(f, 0), source),
				type: parseTypeNode(ts.namedChild(f, 1), source, tparams),
			});
		}
		return { kind: 'record', fields };
	}

	if (kind === 'named_type') {
		let name = ts.text(ts.namedChild(node, 0), source);
		let params = [];
		for (let i = 1; i < ts.namedChildCount(node); i++)
			push(params, parseTypeNode(ts.namedChild(node, i), source, tparams));
		if (tparams[name] && !length(params))
			return { kind: 'param', name };
		// Normalize JSDoc generic aliases to internal representations so that
		// Array<T> and T[] produce identical types and unify correctly.
		if (name === 'Array')
			return { kind: 'generic', base: 'list', params: [length(params) ? params[0] : { kind: 'unknown' }] };
		if (name === 'Object')
			return { kind: 'generic', base: 'dict', params: [length(params) > 1 ? params[1] : { kind: 'unknown' }] };
		return { kind: 'ref', name, params };
	}

	if (kind === 'function_type') {
		let returnNode = ts.childByField(node, 'return');
		let params = [];
		for (let i = 0; i < ts.namedChildCount(node); i++) {
			let child = ts.namedChild(node, i);
			if (ts.nodeType(child) !== 'function_param') continue;
			push(params, {
				name: ts.text(ts.namedChild(child, 0), source),
				type: parseTypeNode(ts.namedChild(child, 1), source, tparams),
			});
		}
		return {
			kind: 'function',
			params,
			return: returnNode ? parseTypeNode(returnNode, source, tparams) : { kind: 'unknown' },
		};
	}

	if (kind === 'anon_function_type') {
		let returnNode = ts.childByField(node, 'return');
		let paramCount = ts.namedChildCount(node) - (returnNode ? 1 : 0);
		let params = [];
		for (let i = 0; i < paramCount; i++)
			push(params, { name: null, type: parseTypeNode(ts.namedChild(node, i), source, tparams) });
		return {
			kind: 'function',
			params,
			return: returnNode ? parseTypeNode(returnNode, source, tparams) : { kind: 'unknown' },
		};
	}

	// One flat node however many members (`a | b | c`).
	if (kind === 'union_type') {
		let members = [];
		for (let i = 0; i < ts.namedChildCount(node); i++)
			push(members, parseTypeNode(ts.namedChild(node, i), source, tparams));
		return { kind: 'union', members };
	}

	if (kind === 'nullable_type') {
		let inner = ts.namedChild(node, 0);
		return { kind: 'nullable', inner: inner ? parseTypeNode(inner, source, tparams) : { kind: 'unknown' } };
	}

	if (kind === 'module_type') {
		let path = ts.childByField(node, 'path');
		return { kind: 'module', path: path ? ts.text(path, source) : '?' };
	}

	if (kind === 'array_type') {
		let elem = ts.namedChild(node, 0);
		return { kind: 'generic', base: 'list', params: [elem ? parseTypeNode(elem, source, tparams) : { kind: 'unknown' }] };
	}

	if (kind === 'parenthesized_type') {
		let inner = ts.namedChild(node, 0);
		return inner ? parseTypeNode(inner, source, tparams) : { kind: 'unknown' };
	}

	return { kind: 'unknown' };
};

// Parse a type_expression or rest_type_expression node — unwraps the braces.
function parseTypeExpr(exprNode, source, tparams) {
	let inner = ts.namedChild(exprNode, 0);
	return inner ? parseTypeNode(inner, source, tparams) : { kind: 'unknown' };
}

// ── Public API ────────────────────────────────────────────────────────────

// Parse a raw /** ... */ comment block into a structured doc object:
// { description, template, params, returns, throws, typedef, deprecated, since }
export function parseDoc(commentText) {
	let tree = ts.parse(_parser, commentText);
	let root = ts.rootNode(tree);

	// First pass: collect @template param names so the type parser can
	// distinguish type params (T) from typedef references (MyType).
	let tparams = {};
	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let node = ts.namedChild(root, i);
		if (ts.nodeType(node) !== 'template_tag') continue;
		for (let j = 0; j < ts.namedChildCount(node); j++)
			tparams[ts.text(ts.namedChild(node, j), commentText)] = true;
	}

	let result = {
		description: null,
		template: keys(tparams),
		params: [],
		returns: null,
		throws: null,
		typedef: null,
		deprecated: null,
		since: null,
		examples: [],
	};

	for (let i = 0; i < ts.namedChildCount(root); i++) {
		let node = ts.namedChild(root, i);
		let ntype = ts.nodeType(node);

		if (ntype === 'description') {
			result.description = descText(node, commentText);

		} else if (ntype === 'param_tag') {
			let typeNode = ts.childByField(node, 'type');
			let nameNode = ts.childByField(node, 'name');
			let descNode = ts.childByField(node, 'description');
			let rest = typeNode !== null && ts.nodeType(typeNode) === 'rest_type_expression';
			let optional = nameNode !== null && ts.nodeType(nameNode) === 'optional_param';
			let name = null;
			// The node that carries the bare name — unwrapped from the `[…]` optional
			// wrapper — so its byte offsets locate the name within the comment (used
			// by consumers that report a diagnostic range on the @param name).
			let nameHolder = null;
			if (nameNode)
				nameHolder = optional ? ts.namedChild(nameNode, 0) : nameNode;
			// A property path `opts.count` documents a field of parameter `opts`:
			// report its root identifier (the grammar parses the whole path as one
			// param_path name).
			if (nameHolder && ts.nodeType(nameHolder) === 'param_path')
				nameHolder = ts.namedChild(nameHolder, 0);
			if (nameHolder)
				name = ts.text(nameHolder, commentText);
			push(result.params, {
				name,
				type: typeNode ? parseTypeExpr(typeNode, commentText, tparams) : null,
				optional,
				rest,
				description: descText(descNode, commentText),
				// Byte offsets of the name within commentText, or null when unnamed.
				nameStart: nameHolder ? ts.startByte(nameHolder) : null,
				nameEnd:   nameHolder ? ts.endByte(nameHolder) : null,
			});

		} else if (ntype === 'returns_tag') {
			let typeNode = ts.childByField(node, 'type');
			let descNode = ts.childByField(node, 'description');
			result.returns = {
				type: typeNode ? parseTypeExpr(typeNode, commentText, tparams) : null,
				description: descText(descNode, commentText),
			};

		} else if (ntype === 'throws_tag') {
			let typeNode = ts.childByField(node, 'type');
			let descNode = ts.childByField(node, 'description');
			result.throws = {
				type: typeNode ? parseTypeExpr(typeNode, commentText, tparams) : null,
				description: descText(descNode, commentText),
			};

		} else if (ntype === 'typedef_tag') {
			let typeNode = ts.childByField(node, 'type');
			let nameNode = ts.childByField(node, 'name');
			result.typedef = {
				name: nameNode ? ts.text(nameNode, commentText) : null,
				type: typeNode ? parseTypeExpr(typeNode, commentText, tparams) : null,
			};

		} else if (ntype === 'deprecated_tag') {
			let descNode = ts.childByField(node, 'description');
			result.deprecated = descNode ? descText(descNode, commentText) : true;

		} else if (ntype === 'since_tag') {
			let descNode = ts.childByField(node, 'description');
			result.since = descText(descNode, commentText);

		} else if (ntype === 'example_tag') {
			let descNode = ts.childByField(node, 'description');
			if (descNode) push(result.examples, descText(descNode, commentText));
		}
	}

	return result;
};

// Render a type object to its source-level string form.
export function typeToString(type) {
	if (!type) return '?';
	let k = type.kind;
	if (k === 'primitive' || k === 'param') return type.name;
	if (k === 'any')     return 'any';
	if (k === 'unknown') return '?';
	if (k === 'module') return 'module:' + type.path;
	if (k === 'generic') return type.base + '<' + join(', ', map(type.params, typeToString)) + '>';
	if (k === 'nullable') return '?' + typeToString(type.inner);
	if (k === 'ref') {
		if (!length(type.params)) return type.name;
		return type.name + '<' + join(', ', map(type.params, typeToString)) + '>';
	}
	if (k === 'union')
		return join(' | ', map(type.members, typeToString));
	if (k === 'record') {
		// Show field names only — field types are accessible by hovering each member.
		return '{ ' + join(', ', map(type.fields, (f) => f.name)) + ' }';
	}
	if (k === 'function') {
		let ps = map(type.params, (p) => (p.name ? p.name + ': ' : '') + typeToString(p.type));
		return '(' + join(', ', ps) + ') => ' + typeToString(type.return);
	}
	return '?';
};
