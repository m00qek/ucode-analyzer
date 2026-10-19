// What each OpenWrt release's ucode lacks: modules its package feed does not
// ship, and module functions, handle methods and builtins added since. Ported
// from noah-lsp (MIT, github.com/NoahBPeterson/ucode-lsp,
// src/analysis/ucodeVersions.ts), which checked them against each release's
// feed and its pinned ucode source. Checked only when the config names a
// `target` release.

// Oldest first. `main` is ucode's own tip, ahead of every release.
const RELEASES = [ '22.03', '23.05', '24.10', '25.12', 'main' ];

// Module → the first release whose feed ships it. Those in every release
// (fs, math, nl80211, resolv, rtnl, struct, ubus, uci, uloop) are not listed.
export const MODULES = {
	io: '25.12', zlib: '25.12', uline: '25.12', pkgen: '25.12',
	digest: '24.10', uclient: '24.10', udebug: '24.10', socket: '24.10',
	debug: '23.05', log: '23.05', bpf: '23.05', html: '23.05', lua: '23.05',
};

// `module.name` → the first release with that function or constant. The
// statvfs ST_* constants are in no release: OpenWrt's musl lacks them.
export const MEMBERS = {
	'fs.mkdtemp': '25.12', 'fs.dup2': '25.12', 'socket.open': '25.12', 'socket.pair': '25.12',
	'fs.IOC_DIR_NONE': '24.10', 'fs.IOC_DIR_READ': '24.10', 'fs.IOC_DIR_WRITE': '24.10', 'fs.IOC_DIR_RW': '24.10',
	'struct.buffer': '24.10', 'uloop.guard': '24.10', 'ubus.open_channel': '24.10', 'ubus.guard': '24.10',
	'fs.pipe': '23.05', 'nl80211.listener': '23.05', 'rtnl.listener': '23.05',
	'uloop.interval': '23.05', 'uloop.signal': '23.05',
	'fs.ST_RDONLY': 'main', 'fs.ST_NOSUID': 'main', 'fs.ST_NODEV': 'main', 'fs.ST_NOEXEC': 'main',
	'fs.ST_SYNCHRONOUS': 'main', 'fs.ST_MANDLOCK': 'main', 'fs.ST_NOATIME': 'main',
	'fs.ST_NODIRATIME': 'main', 'fs.ST_RELATIME': 'main', 'fs.ST_NOSYMFOLLOW': 'main',
};

// The methods of handles (by the typedef the declarations give them) → the
// first release with them.
export const METHODS = {
	FsFile: { ioctl: '24.10', isatty: '23.05', truncate: '23.05', lock: '23.05' },
	UciCursor: { list_append: '24.10', list_remove: '24.10' },
};

// Builtins → the first release with them.
export const BUILTINS = { signal: '23.05' };

let _target = null;

// The release the code runs on, from the config's `target`; false when it
// names none of RELEASES (then nothing is checked).
export function setTarget(release) {
	_target = (release !== null && index(RELEASES, release) >= 0) ? release : null;
	return release === null || _target !== null;
};

// Take the target from config's `target`, warning about a release it does
// not know.
export function configure(config) {
	if (!setTarget(config.target ?? null))
		warn(sprintf("ucode-analyzer: unknown target %J, not one of %s: no release checks\n",
			config.target, join(', ', RELEASES)));
};

export function target() {
	return _target;
};

// True when the target release lacks what `since` added.
export function lacks(since) {
	return _target !== null && since !== null && index(RELEASES, _target) < index(RELEASES, since);
};

export function names() {
	return RELEASES;
};
