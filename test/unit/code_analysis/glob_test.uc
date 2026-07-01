import { describe, it, assert } from 'utest';
import { matchPattern, scan } from 'code_analysis.glob';

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
		let all  = scan('/app/src', ['**/*.uc'], []);
		let excl = scan('/app/src', ['**/*.uc'], ['language_server/**']);

		assert.match(true, length(excl) < length(all));
		for (let f in excl)
			assert.match(false, index(f, 'language_server') >= 0);
	});

	it('returns empty list when no files match', () => {
		let files = scan('/app/src', ['**/*.lua'], []);
		assert.match(0, length(files));
	});
});
