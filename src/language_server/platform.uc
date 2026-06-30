import * as fs from 'fs';
import * as uloop from 'uloop';

let _index    = {};   // uri → version index (-1 = not installed)
let _versions = {};   // uri → versions array
let _pkgMgr   = null; // 'apk' | 'opkg' | '' (detected-none) | null (not yet checked)
let _pkgTask  = null; // background uloop.task running the package-manager queries

function modNameFromUri(uri) {
	let i = length(uri) - 1;
	while (i >= 0 && substr(uri, i, 1) !== '/') i--;
	let filename = substr(uri, i + 1);
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

function queryApk(modName) {
	let pkg = 'ucode-mod-' + modName;
	// Output: "ucode-mod-fs-2026.01.16~85922056-r1 x86_64 ... [installed]"
	let f = fs.popen('apk list --installed ' + pkg + ' 2>/dev/null', 'r');
	if (!f) return null;
	let line = f.read('line');
	f.close();
	if (!line) return null;
	let prefix = pkg + '-';
	let first = split(trim(line), ' ')[0];
	if (!first || substr(first, 0, length(prefix)) !== prefix) return null;
	return stripRevision(substr(first, length(prefix)));
}

function queryOpkg(modName) {
	let pkg = 'ucode-mod-' + modName;
	let f = fs.popen('opkg status ' + pkg + ' 2>/dev/null', 'r');
	if (!f) return null;
	let version = null;
	let line;
	while ((line = f.read('line')) !== null) {
		let m = match(line, /^Version: (.+)/);
		if (m) { version = stripRevision(m[1]); break; }
	}
	f.close();
	return version;
}

function installedVersion(modName) {
	let mgr = detectPkgMgr();
	if (!mgr) return null;
	return (mgr === 'apk') ? queryApk(modName) : queryOpkg(modName);
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
	_index = computeIndex(declVersions, queryFn ?? installedVersion);
};

// Async init for production. The apk/opkg lookups are blocking subprocess calls
// (one per declaration module), so they run in a forked uloop.task to keep the
// event loop responsive during startup. Until the task finishes, _index is empty
// and module/symbol checks default to "available" — no false unavailability.
// onComplete fires once the index is populated, letting the caller refresh.
export function initAsync(declVersions, onComplete) {
	storeVersions(declVersions);
	_index = {};
	_pkgTask = uloop.task(
		function(pipe) {
			pipe.send(computeIndex(declVersions, installedVersion));
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
