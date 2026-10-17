import * as fs from 'fs';
import * as uloop from 'uloop';

let _index    = {};   // uri → version index (-1 = not installed)
let _versions = {};   // uri → versions array
let _pkgMgr   = null; // 'apk' | 'opkg' | '' (detected-none) | null (not yet checked)
let _pkgTask  = null; // background uloop.task running the package-manager queries

function modNameFromUri(uri) {
	let filename = fs.basename(uri);
	return substr(filename, 0, length(filename) - 5); // strip ".d.uc"
}

function stripRevision(v) {
	return replace(trim(v), /-r[0-9]+$/, '');
}

function detectPkgMgr() {
	if (_pkgMgr !== null) return _pkgMgr || null;
	let s = fs.stat('/usr/bin/apk');
	if (s && s.type === 'file') { _pkgMgr = 'apk';  return 'apk'; }
	s = fs.stat('/usr/bin/opkg');
	if (s && s.type === 'file') { _pkgMgr = 'opkg'; return 'opkg'; }
	_pkgMgr = '';
	return null;
}

// Split an apk "<name>-<version>" token: the version starts at the first '-'
// followed by a digit ("ucode-mod-nl80211-2026.01.16~85922056-r1").
function splitApkToken(token) {
	for (let i = 0; i < length(token) - 1; i++)
		if (substr(token, i, 1) === '-' && match(substr(token, i + 1, 1), /[0-9]/))
			return [substr(token, 0, i), substr(token, i + 1)];
	return null;
}

// Every installed ucode-mod-* package as { modName → version }, from ONE
// package-manager call (not one subprocess per declaration module).
//   apk:  "ucode-mod-fs-2026.01.16~85922056-r1 x86_64 {…} (ISC) [installed]"
//   opkg: "ucode-mod-fs - 2025.07.18~3f64c808-r1"
function listInstalled(mgr) {
	let installed = {};
	let f = fs.popen((mgr === 'apk')
		? 'apk list --installed 2>/dev/null'
		: 'opkg list-installed 2>/dev/null', 'r');
	if (!f) return installed;
	let line;
	while ((line = f.read('line')) !== null && line !== '') {
		let name, version;
		if (mgr === 'apk') {
			let nv = splitApkToken(split(trim(line), ' ')[0]);
			if (!nv) continue;
			name = nv[0];
			version = nv[1];
		} else {
			let m = match(trim(line), /^([^ ]+) - ([^ ]+)/);
			if (!m) continue;
			name = m[1];
			version = m[2];
		}
		if (substr(name, 0, 10) === 'ucode-mod-')
			installed[substr(name, 10)] = stripRevision(version);
	}
	f.close();
	return installed;
}

// A `modName → installed-version | null` query backed by a single, lazy
// listInstalled() call. A fresh one per init, so each init sees the packages
// installed at that time.
function packageQuery() {
	let installed = null;
	return function(modName) {
		let mgr = detectPkgMgr();
		if (!mgr) return null;
		if (installed === null)
			installed = listInstalled(mgr);
		return installed[modName] ?? null;
	};
}

// Compute the { uri → installed-version index } map (-1 = not installed) for
// declVersions, using `query(modName) → version-string | null`. Pure and
// synchronous so it can run inline (tests) or inside the background task.
function computeIndex(declVersions, query) {
	let idxMap = {};
	for (let uri in declVersions) {
		let versions = declVersions[uri];
		if (!versions || length(versions) === 0) continue;

		let modName = modNameFromUri(uri);

		if (modName === 'global') {
			idxMap[uri] = length(versions) - 1;
			continue;
		}

		let installed = query(modName);
		if (!installed) {
			idxMap[uri] = -1;
			continue;
		}

		let idx = index(versions, installed);
		idxMap[uri] = (idx >= 0) ? idx : (length(versions) - 1);
	}
	return idxMap;
}

function storeVersions(declVersions) {
	_versions = {};
	for (let uri in declVersions) {
		let versions = declVersions[uri];
		if (versions && length(versions) > 0)
			_versions[uri] = versions;
	}
}

// Synchronous init. declVersions: { uri → versions[] }.
// queryFn is optional; when provided it replaces the real package-manager query
// (Signature: queryFn(modName) → installed-version-string | null). This seam
// lets tests inject a known answer without a real package manager.
export function init(declVersions, queryFn) {
	storeVersions(declVersions);
	_index = computeIndex(declVersions, queryFn ?? packageQuery());
};

// Async init for production. The apk/opkg listing is a blocking subprocess call,
// so it runs in a forked uloop.task to keep the event loop responsive during
// startup. Until the task finishes, _index is empty and module/symbol checks
// default to "available" — no false unavailability.
// onComplete fires once the index is populated, letting the caller refresh.
export function initAsync(declVersions, onComplete) {
	storeVersions(declVersions);
	_index = {};
	_pkgTask = uloop.task(
		function(pipe) {
			signal('SIGTERM', 'default');  // so cancel() can kill it; see parallel.uc
			pipe.send(computeIndex(declVersions, packageQuery()));
		},
		function(idxMap) {
			if (idxMap === null) {   // uloop task-completion sentinel
				_pkgTask = null;
				return;
			}
			_index = idxMap;
			if (onComplete) onComplete();
		}
	);
};

// Kill the background package-query task if one is still running (server
// teardown). Without this the forked child is orphaned/reparented to init and
// keeps running its apk/opkg probes after the server exits.
export function cancel() {
	if (_pkgTask) {
		_pkgTask.kill();
		_pkgTask = null;
	}
};

// Returns false only when we have version info AND the module is not installed.
export function moduleAvailable(modUri) {
	if (!exists(_index, modUri)) return true;
	return _index[modUri] >= 0;
};

// Returns false when the symbol's @since is newer than what is installed.
export function symbolAvailable(modUri, sinceVersion) {
	if (!exists(_index, modUri)) return true;
	let vIdx = _index[modUri];
	if (vIdx < 0) return false;
	if (!sinceVersion) return true;
	let versions = _versions[modUri];
	if (!versions) return true;
	let sinceIdx = index(versions, sinceVersion);
	if (sinceIdx < 0) return true; // unknown version → show anyway
	return sinceIdx <= vIdx;
};
