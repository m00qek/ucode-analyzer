// Legacy ucode module: exports via a top-level `return { ... }` object
// (the classic require() shape) rather than ES `export` statements.
function reset() { return 0; }

return {
	greet: function(name) { return name; },
	reset,
	version: 2,
};
