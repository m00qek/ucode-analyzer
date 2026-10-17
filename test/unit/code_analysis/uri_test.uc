import { describe, it, assert } from 'utest';
import { toPath } from 'ucode_analyzer.code_analysis.uri';

describe('uri', () => {
	it('gives the path of a file:// URI', () => {
		assert.match('/app/a.uc', toPath('file:///app/a.uc'));
	});

	it('leaves any other URI as it is', () => {
		assert.match('untitled:Untitled-1', toPath('untitled:Untitled-1'));
	});
});
