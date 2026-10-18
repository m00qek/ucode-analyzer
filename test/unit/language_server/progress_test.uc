import { describe, it, assert } from 'utest';
import { newProgress } from 'ucode_analyzer.language_server.progress';

// A progress whose notifications land in `sent`, as their values.
function capture() {
	let sent = [];
	let p = newProgress('tok', 'Indexing', (method, params) => {
		assert.match([ '$/progress', 'tok' ], [ method, params.token ]);
		push(sent, params.value);
	});
	return { p, sent };
}

describe('progress', () => {
	it('sends nothing until the client accepts the token', () => {
		let c = capture();
		c.p.report(10, 100);
		c.p.end('done');
		assert.match([], c.sent);
	});

	it('begins where the work is, then reports in 5% steps, then ends', () => {
		let c = capture();
		c.p.report(3, 100);
		c.p.accepted(true);
		for (let i = 4; i <= 100; i++) c.p.report(i, 100);
		c.p.end('100 files');
		assert.match({ kind: 'begin', title: 'Indexing', percentage: 3, message: '3/100 files', cancellable: false }, c.sent[0]);
		assert.match([ 8, 13, 18, 23, 28, 33, 38, 43, 48, 53, 58, 63, 68, 73, 78, 83, 88, 93, 98 ],
			map(slice(c.sent, 1, -1), (v) => v.percentage));
		assert.match({ kind: 'end', message: '100 files' }, c.sent[-1]);
	});

	it('accepted after the work ended: begins and ends at once', () => {
		let c = capture();
		c.p.report(50, 50);
		c.p.end('50 files');
		c.p.accepted(true);
		assert.match([ 'begin', 'end' ], map(c.sent, (v) => v.kind));
		assert.match('50 files', c.sent[1].message);
	});

	it('sends nothing when the client refuses the token', () => {
		let c = capture();
		c.p.accepted(false);
		c.p.report(50, 100);
		c.p.end('done');
		assert.match([], c.sent);
	});
});
