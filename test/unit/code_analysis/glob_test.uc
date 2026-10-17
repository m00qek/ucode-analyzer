import { describe, it, assert, prop, gen } from 'utest';
import { matchPattern, scan } from 'ucode_analyzer.code_analysis.glob';
import * as fs from 'fs';

describe('glob.matchPattern', () => {
	it('matches ** at start', () => {
		assert.match(true, matchPattern('**/*.uc', 'foo.uc'));
		assert.match(true, matchPattern('**/*.uc', 'src/foo.uc'));
		assert.match(true, matchPattern('**/*.uc', 'a/b/c/foo.uc'));
		assert.match(false, matchPattern('**/*.uc', 'src/foo.js'));
	});

	it('matches ** in middle', () => {
		assert.match(true, matchPattern('src/**/*.uc', 'src/foo.uc'));
		assert.match(true, matchPattern('src/**/*.uc', 'src/a/foo.uc'));
		assert.match(true, matchPattern('src/**/*.uc', 'src/a/b/foo.uc'));
		assert.match(false, matchPattern('src/**/*.uc', 'other/foo.uc'));
	});

	it('matches ** at end', () => {
		assert.match(true, matchPattern('build/**', 'build/foo.uc'));
		assert.match(true, matchPattern('build/**', 'build/a/b/foo'));
		assert.match(false, matchPattern('build/**', 'src/foo.uc'));
	});

	it('matches * within a segment', () => {
		assert.match(true, matchPattern('*.uc', 'foo.uc'));
		assert.match(false, matchPattern('*.uc', 'src/foo.uc'));
	});

	it('matches literal paths exactly', () => {
		assert.match(true, matchPattern('src/foo.uc', 'src/foo.uc'));
		assert.match(false, matchPattern('src/foo.uc', 'src/bar.uc'));
	});

	it('escapes regex special chars in literal parts', () => {
		assert.match(true, matchPattern('src/a+b.uc', 'src/a+b.uc'));
		assert.match(false, matchPattern('src/a+b.uc', 'src/aXb.uc'));
	});
});

describe('glob.scan', () => {
	it('finds .uc files matching include pattern', () => {
		let files = scan('/app/src', ['**/*.uc'], []);
		assert.match(true, length(files) > 0);
		for (let f in files)
			assert.match(true, index(f, '.uc') >= 0);
	});

	it('excludes paths matching exclude pattern', () => {
		let all  = scan('/app/src/ucode_analyzer', ['**/*.uc'], []);
		let excl = scan('/app/src/ucode_analyzer', ['**/*.uc'], ['language_server/**']);

		assert.match(true, length(excl) < length(all));
		for (let f in excl)
			assert.match(false, index(f, 'language_server') >= 0);
	});

	it('does not enter an excluded directory', () => {
		let root = '/tmp/glob-prune';
		system(sprintf('rm -rf %s', root));
		fs.mkdir(root);
		fs.mkdir(root + '/.git');
		fs.writefile(root + '/.git/x.uc', 'let x = 1;\n');
		fs.writefile(root + '/a.uc', 'let a = 1;\n');

		let files = scan(root, ['**/*.uc'], ['**/.*/**']);
		system(sprintf('rm -rf %s', root));

		assert.match([root + '/a.uc'], files);
	});

	it('returns empty list when no files match', () => {
		let files = scan('/app/src', ['**/*.lua'], []);
		assert.match(0, length(files));
	});

	it('follows a symlink back up the tree only once', () => {
		let root = '/tmp/glob-loop';
		system(sprintf('rm -rf %s', root));
		fs.mkdir(root);
		fs.mkdir(root + '/src');
		fs.writefile(root + '/src/a.uc', 'let a = 1;\n');
		fs.symlink('..', root + '/src/loop');

		let files = scan(root + '/src', ['**/*.uc'], []);
		system(sprintf('rm -rf %s', root));

		assert.match([root + '/src/a.uc'], files);
	});

	it('follows a symlinked directory outside the tree', () => {
		let root = '/tmp/glob-link';
		system(sprintf('rm -rf %s', root));
		fs.mkdir(root);
		fs.mkdir(root + '/shared');
		fs.mkdir(root + '/src');
		fs.writefile(root + '/shared/b.uc', 'let b = 1;\n');
		fs.symlink('../shared', root + '/src/lib');

		let files = scan(root + '/src', ['**/*.uc'], []);
		system(sprintf('rm -rf %s', root));

		assert.match([root + '/src/lib/b.uc'], files);
	});
});

// ---------------------------------------------------------------------------
// Property-based tests: a literal path used as its own glob pattern must match
// itself, even when it is riddled with regex metacharacters. This is exactly
// the property globToRegex's escape set exists to guarantee — every character
// in _special is escaped so it matches literally rather than acting as a regex
// operator. The charset deliberately excludes the two glob wildcards ('*','?')
// and the path separator ('/'), which are the only characters that are *not*
// meant to match themselves literally.
// ---------------------------------------------------------------------------

let META_CHARSET = "abAB01.+-_(){}[]^$|";

// A path segment of 1–5 metachar-laden characters, no wildcards / separators.
let SEGMENT = gen.string({ min_len: 1, max_len: 5, charset: META_CHARSET });

// Join 1–3 segments with '/'.
function joinSegs(segs) {
	let path = '';
	for (let i = 0; i < length(segs); i++)
		path += (i > 0 ? '/' : '') + segs[i];
	return path;
}

describe('glob.matchPattern — properties', () => {
	prop('a literal path matches itself as a pattern (metachars escaped)',
		gen.array(SEGMENT, { min_len: 1, max_len: 3 }),
		(segs, ctx) => {
			let path = joinSegs(segs);
			ctx.classify('has-dot',    index(path, '.') >= 0);
			ctx.classify('has-bracket', index(path, '[') >= 0 || index(path, '{') >= 0);
			assert.match(true, matchPattern(path, path),
				sprintf('%s did not self-match', path));
		});

	prop('the pattern is anchored — a longer pattern never matches a prefix path',
		gen.array(SEGMENT, { min_len: 1, max_len: 3 }),
		(segs) => {
			let path = joinSegs(segs);
			// 'Q' is a plain literal (not a wildcard), so path+'Q' is strictly
			// longer than path; the ^…$ anchoring must reject the shorter subject.
			assert.match(false, matchPattern(path + 'Q', path),
				sprintf('%sQ wrongly matched %s', path, path));
		});
});
