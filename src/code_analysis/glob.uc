import * as fs from 'fs';

let _special = {
	'.': true, '+': true, '(': true, ')': true, '{': true,
	'}': true, '[': true, ']': true, '^': true, '$': true,
	'|': true, '\\': true,
};

function globToRegex(pattern) {
	let re = '^';
	let i = 0;
	let n = length(pattern);

	while (i < n) {
		let c = substr(pattern, i, 1);

		if (c === '*') {
			if (i + 1 < n && substr(pattern, i + 1, 1) === '*') {
				if (i + 2 < n && substr(pattern, i + 2, 1) === '/') {
					re += '(.*/)?';
					i += 3;
				} else {
					re += '.*';
					i += 2;
				}
			} else {
				re += '[^/]*';
				i++;
			}
		} else if (c === '?') {
			re += '[^/]';
			i++;
		} else if (_special[c]) {
			re += '\\' + c;
			i++;
		} else {
			re += c;
			i++;
		}
	}

	return regexp(re + '$');
}

function matchesPattern(relPath, pattern) {
	return match(relPath, globToRegex(pattern)) !== null;
}

function matchesAny(relPath, patterns) {
	for (let p in patterns) {
		if (matchesPattern(relPath, p))
			return true;
	}
	return false;
}

function walkDir(absDir, relDir, includes, excludes, results) {
	let dir = fs.opendir(absDir);
	if (!dir) return;

	let entry;
	while ((entry = dir.read()) !== null) {
		if (entry === '.' || entry === '..') continue;

		let absPath = absDir + '/' + entry;
		let relPath = relDir !== '' ? relDir + '/' + entry : entry;
		let stat = fs.stat(absPath);

		if (!stat) continue;

		if (stat.type === 'directory') {
			walkDir(absPath, relPath, includes, excludes, results);
		} else {
			if (matchesAny(relPath, includes) && !matchesAny(relPath, excludes))
				push(results, absPath);
		}
	}

	dir.close();
}

// Returns absolute paths of files under dir matching includes/excludes.
export function scan(dir, includes, excludes) {
	let results = [];
	walkDir(dir, '', includes, excludes ?? [], results);
	return results;
};

export function matchPattern(pattern, relPath) {
	return matchesPattern(relPath, pattern);
};
