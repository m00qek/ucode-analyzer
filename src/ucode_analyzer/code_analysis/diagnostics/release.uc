// Code that the configured target release cannot run: an import of a module
// its feed does not ship, or a module member, handle method or builtin it
// lacks (releases.uc). Silent unless the config names a target.

import * as ts from 'tree_sitter';
import * as releases from 'ucode_analyzer.code_analysis.releases';
import { stringLiteralText } from 'ucode_analyzer.code_analysis.ast_text';
import { inferNode } from 'ucode_analyzer.code_analysis.types.inferrer';
import { scopeHas, isRootBinding } from 'ucode_analyzer.code_analysis.types.scope';
import { scopeAtOffset } from 'ucode_analyzer.code_analysis.types.scope_walk';
import { offsetToPosition } from 'ucode_analyzer.code_analysis.positions';
import { Severity, diagnostic } from 'ucode_analyzer.code_analysis.lsp_types';

function flag(node, what, since, doc, out) {
	if (!releases.lacks(since)) return;
	let message = (since === 'main')
		? sprintf("%s is in no OpenWrt release, %s included", what, releases.target())
		: sprintf("%s is not in OpenWrt %s: it came in %s", what, releases.target(), since);
	push(out, diagnostic({
		start: offsetToPosition(doc.text, doc.lineTable, ts.startByte(node)),
		end:   offsetToPosition(doc.text, doc.lineTable, ts.endByte(node)),
	}, Severity.WARNING, 'not-in-release', message));
}

// True when name, used at node, is the builtin rather than a local binding.
function isBuiltin(node, name, doc) {
	let scope = scopeAtOffset(doc.scopeMap, ts.startByte(node));
	return !scopeHas(scope, name) || isRootBinding(scope, name);
}

function checkImport(stmt, doc, out) {
	let src = ts.childByField(stmt, 'source');
	if (!src || ts.nodeType(src) !== 'string') return;
	let mod = stringLiteralText(src, doc.text);
	flag(src, sprintf("Module '%s'", mod), releases.MODULES[mod], doc, out);
	for (let spec in ts.descendants(stmt, [ 'import_specifier' ])) {
		let name = ts.childByField(spec, 'name');
		if (name) flag(name, sprintf("'%s.%s'", mod, ts.text(name, doc.text)),
			releases.MEMBERS[mod + '.' + ts.text(name, doc.text)], doc, out);
	}
}

function checkCall(call, doc, out) {
	let callee = ts.childByField(call, 'function');
	if (!callee || ts.nodeType(callee) !== 'identifier') return;
	let name = ts.text(callee, doc.text);
	if (name === 'require') {
		let args = ts.namedChildren(ts.childByField(call, 'arguments'));
		if (length(args) && ts.nodeType(args[0]) === 'string' && isBuiltin(call, 'require', doc)) {
			let mod = stringLiteralText(args[0], doc.text);
			flag(args[0], sprintf("Module '%s'", mod), releases.MODULES[mod], doc, out);
		}
	} else if (releases.BUILTINS[name] && isBuiltin(call, name, doc)) {
		flag(callee, sprintf("'%s()'", name), releases.BUILTINS[name], doc, out);
	}
}

function checkMember(member, uri, doc, out) {
	let obj = ts.childByField(member, 'object'), prop = ts.childByField(member, 'property');
	if (!obj || !prop || ts.nodeType(prop) !== 'property_identifier') return;
	let name = ts.text(prop, doc.text);
	let t = inferNode(obj, doc.text, uri, scopeAtOffset(doc.scopeMap, ts.startByte(obj)), 0);
	if (t?.kind === 'nullable') t = t.inner;
	if (t?.kind === 'module')
		flag(prop, sprintf("'%s.%s'", t.path, name), releases.MEMBERS[t.path + '.' + name], doc, out);
	else if (t?.kind === 'ref' && releases.METHODS[t.name])
		flag(prop, sprintf("'%s()'", name), releases.METHODS[t.name][name], doc, out);
}

export function releaseChecks(uri, doc) {
	if (!releases.target()) return [];
	let out = [];
	let root = ts.rootNode(doc.tree);
	for (let n in ts.descendants(root, [ 'import_statement', 'call_expression', 'member_expression' ])) {
		let t = ts.nodeType(n);
		if (t === 'import_statement') checkImport(n, doc, out);
		else if (t === 'call_expression') checkCall(n, doc, out);
		else checkMember(n, uri, doc, out);
	}
	return out;
};
