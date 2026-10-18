// A module with the shapes an incremental scope map must get right: functions
// reading top-level state, captured variables, callbacks, optional chains,
// guards, JSDoc and the methods of a returned object.

import * as fs from 'fs';

let state = null;
let count = 0;
const LIMIT = 16;

/**
 * @param {string} path
 * @returns {?string}
 */
function slurp(path) {
	let fd = fs.open(path, 'r');
	if (!fd) return null;
	let data = fd.read('all');
	fd.close();
	return data;
}

function parse_line(line) {
	let m = match(line, /^([a-z]+)=(.*)$/);
	if (!m) return null;
	return { key: m[1], value: m[2] };
}

function load(path) {
	let text = slurp(path);
	let out = {};
	for (let line in split(text ?? '', '\n')) {
		let kv = parse_line(line);
		if (kv == null) continue;
		out[kv.key] = kv.value;
		count++;
	}
	state = out;
	return out;
}

function lookup(key) {
	let v = state?.[key];
	if (v == null) return LIMIT;
	return +v;
}

function each(list, cb) {
	for (let i = 0; i < length(list); i++)
		cb(list[i], i);
}

function last(list) {
	let found = null;
	each(list, (x) => { found = x; });
	return found;
}

let timer = null;
let stop = () => { if (timer) timer.cancel(); timer = null; };

function code_of(reply) {
	let code = reply?.status?.code;
	if (code == null) return -1;
	return reply.status.code;
}

function kinds(objs) {
	let seen = {};
	for (let o in objs) {
		if (type(o) != 'object') continue;
		seen[o.kind ?? 'none'] = true;
	}
	return sort(keys(seen));
}

return {
	name: 'incremental',

	init: function(path) {
		this.config = load(path ?? '/etc/config');
		return this;
	},

	size: function() {
		return length(state ?? {}) + count;
	},

	get: function(key, fallback) {
		let v = lookup(key);
		return (v > LIMIT) ? fallback : v;
	},

	tail: function(list) {
		let t = last(list);
		while (t && t.next)
			t = t.next;
		return t;
	},

	describe: function(reply) {
		let c = code_of(reply);
		switch (c) {
		case 200:
			return 'ok';
		case -1:
			return 'none';
		default:
			return sprintf('code %d', c);
		}
	},

	close: function() {
		stop();
		return kinds([ state, { kind: 'closed' } ]);
	},
};
