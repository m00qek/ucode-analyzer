'use strict';

import { describe, it, assert } from 'utest';
import * as dag from 'code_analysis.dag.dag';

import * as mod_bpf     from 'bpf';
import * as mod_debug   from 'debug';
import * as mod_digest  from 'digest';
import * as mod_fs      from 'fs';
import * as mod_io      from 'io';
import * as mod_log     from 'log';
import * as mod_lua     from 'lua';
import * as mod_math    from 'math';
import * as mod_nl80211 from 'nl80211';
import * as mod_pkgen   from 'pkgen';
import * as mod_resolv  from 'resolv';
import * as mod_rtnl    from 'rtnl';
import * as mod_socket  from 'socket';
import * as mod_struct  from 'struct';
import * as mod_ubus    from 'ubus';
import * as mod_uci     from 'uci';
import * as mod_uclient from 'uclient';
import * as mod_udebug  from 'udebug';
import * as mod_uline   from 'uline';
import * as mod_uloop   from 'uloop';
import * as mod_zlib    from 'zlib';

const DECL = '/app/src/declarations';

const RESERVED_WORDS = [ 'const', 'let', 'var', 'function', 'class', 'import', 'export',
                          'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case',
                          'break', 'continue', 'default', 'delete', 'typeof', 'instanceof',
                          'in', 'of', 'true', 'false', 'null', 'this', 'super', 'void' ];

function liveKeys(mod) {
	let result = [];
	for (let k in mod) if (index(RESERVED_WORDS, k) < 0) push(result, k);
	return result;
}

function declaredKeys(path) {
	let uri = 'file://' + path;
	dag.addFromDisk(uri);
	return map(dag.exportsOf(uri) ?? [], (e) => e.name);
}

function check(mod, declFile) {
	let live     = liveKeys(mod);
	let declared = declaredKeys(declFile);
	let missing  = filter(live,     (k) => index(declared, k) < 0);
	let stale    = filter(declared, (k) => index(live, k) < 0);
	return { missing, stale };
}

describe('declarations match live modules', () => {
	let cases = [
		[ 'bpf',     mod_bpf,     DECL + '/bpf.d.uc'     ],
		[ 'debug',   mod_debug,   DECL + '/debug.d.uc'   ],
		[ 'digest',  mod_digest,  DECL + '/digest.d.uc'  ],
		[ 'fs',      mod_fs,      DECL + '/fs.d.uc'      ],
		[ 'io',      mod_io,      DECL + '/io.d.uc'      ],
		[ 'log',     mod_log,     DECL + '/log.d.uc'     ],
		[ 'lua',     mod_lua,     DECL + '/lua.d.uc'     ],
		[ 'math',    mod_math,    DECL + '/math.d.uc'    ],
		[ 'nl80211', mod_nl80211, DECL + '/nl80211.d.uc' ],
		[ 'pkgen',   mod_pkgen,   DECL + '/pkgen.d.uc'   ],
		[ 'resolv',  mod_resolv,  DECL + '/resolv.d.uc'  ],
		[ 'rtnl',    mod_rtnl,    DECL + '/rtnl.d.uc'    ],
		[ 'socket',  mod_socket,  DECL + '/socket.d.uc'  ],
		[ 'struct',  mod_struct,  DECL + '/struct.d.uc'  ],
		[ 'ubus',    mod_ubus,    DECL + '/ubus.d.uc'    ],
		[ 'uci',     mod_uci,     DECL + '/uci.d.uc'     ],
		[ 'uclient', mod_uclient, DECL + '/uclient.d.uc' ],
		[ 'udebug',  mod_udebug,  DECL + '/udebug.d.uc'  ],
		[ 'uline',   mod_uline,   DECL + '/uline.d.uc'   ],
		[ 'uloop',   mod_uloop,   DECL + '/uloop.d.uc'   ],
		[ 'zlib',    mod_zlib,    DECL + '/zlib.d.uc'    ],
	];

	for (let c in cases) {
		let name = c[0], mod = c[1], declFile = c[2];
		it(name, () => {
			let r = check(mod, declFile);
			assert.match([], r.missing, name + ': live keys not in declaration: ' + join(', ', r.missing));
			assert.match([], r.stale,   name + ': declared keys absent in live module: ' + join(', ', r.stale));
		});
	}
});
