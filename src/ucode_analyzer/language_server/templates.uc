import * as fs from 'fs';

// Resolved template paths, keyed by template name.
// null means the template was looked for but not found.
let _cache = {};

// Return the path of the first existing file for name, checking
// configDir before selfSrcDir. Returns null if neither exists.
export function resolveTemplate(name, config) {
	if (exists(_cache, name)) return _cache[name];
	let candidates = [];
	if (config.configDir)  push(candidates, config.configDir  + '/templates/' + name + '.uc');
	if (config.selfSrcDir) push(candidates, config.selfSrcDir + '/language_server/templates/' + name + '.uc');
	for (let p in candidates) {
		if (fs.stat(p)) { _cache[name] = p; return p; }
	}
	_cache[name] = null;
	return null;
};

// Render a template file, capturing its output as a string.
// All ctx fields (label, typeStr, doc, params, ...) are available as
// globals inside the template — no preamble needed.
// Templates use {% %} / {{ }} ucode template syntax.
export function renderTemplate(name, ctx, config) {
	let path = resolveTemplate(name, config);
	if (!path) return null;
	return render(path, ctx);
};

// Discard cached resolution results (used in tests between cases).
export function resetCache() {
	_cache = {};
};
