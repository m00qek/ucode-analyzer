import { describe, it, assert } from 'utest';
import * as uloop from 'uloop';
import { shardRoundRobin, fanOut, jobsFor } from 'ucode_analyzer.code_analysis.parallel';

// [0, 1, …, n-1]
function nums(n) {
	let a = [];
	for (let i = 0; i < n; i++) push(a, i);
	return a;
}

describe('parallel — shardRoundRobin', () => {
	it('creates exactly `jobs` shards', () => {
		assert.match(3, length(shardRoundRobin(nums(10), 3)));
	});

	it('assigns every item exactly once (no loss, no duplication)', () => {
		let shards = shardRoundRobin(nums(10), 3);
		let total = 0;
		let seen = {};
		for (let s in shards)
			for (let x in s) { total++; seen[x] = (seen[x] ?? 0) + 1; }
		assert.match(10, total);
		for (let i = 0; i < 10; i++)
			assert.match(1, seen[i]);
	});

	it('spreads work evenly (round-robin, sizes differ by at most one)', () => {
		let shards = shardRoundRobin(nums(10), 3);
		assert.match(4, length(shards[0]));   // items 0,3,6,9
		assert.match(3, length(shards[1]));   // items 1,4,7
		assert.match(3, length(shards[2]));   // items 2,5,8
	});

	it('places item i in shard (i % jobs)', () => {
		let shards = shardRoundRobin(nums(7), 3);
		assert.match(0, shards[0][0]);
		assert.match(3, shards[0][1]);
		assert.match(1, shards[1][0]);
		assert.match(2, shards[2][0]);
	});

	it('leaves empty shards when jobs exceed items', () => {
		let shards = shardRoundRobin(nums(2), 4);
		assert.match(4, length(shards));
		assert.match(1, length(shards[0]));
		assert.match(1, length(shards[1]));
		assert.match(0, length(shards[2]));
		assert.match(0, length(shards[3]));
	});

	it('a single job holds all items in order', () => {
		let shards = shardRoundRobin(nums(5), 1);
		assert.match(1, length(shards));
		assert.match(5, length(shards[0]));
		assert.match(0, shards[0][0]);
		assert.match(4, shards[0][4]);
	});
});

describe('parallel — fanOut', () => {
	// The forking path is exercised end-to-end by the LSP workspace/diagnostic and
	// CLI linter suites (both run at detectJobs() >= 2 on a 2-vCPU runner). Here we
	// pin the non-forking contract: an empty workload must still drive the caller's
	// completion path so its uniform teardown/respond logic fires regardless of size.
	it('invokes onDone immediately and forks nothing for an empty item list', () => {
		let doneCalled = false;
		let itemCalls  = 0;
		let tasks = fanOut([], 4,
			(x) => x,
			(_) => { itemCalls++; },
			()  => { doneCalled = true; });

		assert.match(true, doneCalled);
		assert.match(0, itemCalls);
		assert.match(0, length(tasks));
	});
});

// Run fanOut on a fresh event loop until it reports completion (or a 5 s
// safety timeout). Returns the results in arrival order and how many times
// onDone fired.
function runFanOut(items, jobs, work) {
	let results = [];
	let doneCount = 0;
	uloop.init();
	let timeout = uloop.timer(5000, () => uloop.end());
	fanOut(items, jobs, work,
		(r) => push(results, r),
		()  => { doneCount++; uloop.end(); });
	uloop.run();
	if (timeout) timeout.cancel();
	return { results, doneCount };
}

describe('parallel — fanOut across worker processes', () => {
	it('delivers every result exactly once and completes once', () => {
		let r = runFanOut(nums(10), 3, (x) => x * 2);
		assert.match(1, r.doneCount);
		assert.match([0, 2, 4, 6, 8, 10, 12, 14, 16, 18], sort(r.results));
	});

	it('delivers a null result as an item, not as the end of a worker', () => {
		let r = runFanOut(nums(4), 2, (x) => (x % 2) ? x : null);
		assert.match(1, r.doneCount);
		assert.match(4, length(r.results));
		assert.match(2, length(filter(r.results, (v) => v === null)));
	});

	it('skips an item whose work throws and still completes', () => {
		let r = runFanOut(nums(6), 2, (x) => { if (x === 3) die('boom'); return x; });
		assert.match(1, r.doneCount);
		assert.match([0, 1, 2, 4, 5], sort(r.results));
	});

	it('completes when a worker process dies before finishing its shard', () => {
		// exit() cannot be caught inside the worker: it ends the process, like a
		// crash, without the worker ever reporting completion.
		let r = runFanOut(nums(6), 2, (x) => { if (x === 1) exit(1); return x; });
		assert.match(1, r.doneCount);
		// Worker 0 (items 0, 2, 4) finishes; worker 1 dies at its first item.
		assert.match([0, 2, 4], sort(r.results));
	});

	it('kill() stops a worker while the parent handles SIGTERM', () => {
		// As the LSP does: its workers inherit this handler.
		uloop.init();
		let sig = uloop.signal('SIGTERM', () => uloop.end());
		let doneCount = 0;
		let tasks = fanOut([0], 1,
			(x) => { for (let i = 0; i < 1000000000; i++); return x; },
			(_) => null,
			()  => { doneCount++; uloop.end(); });
		uloop.timer(100, () => tasks[0].kill());
		// The watchdog completes the fan-out once the killed worker has exited.
		let timeout = uloop.timer(3000, () => uloop.end());
		uloop.run();
		if (timeout) timeout.cancel();
		if (sig) sig.delete();
		let stopped = tasks[0].finished();
		// A surviving worker would keep the test run from exiting.
		if (!stopped) system(sprintf('kill -9 %d', tasks[0].pid()));
		assert.match(true, stopped);
		assert.match(1, doneCount);
	});
});

describe('parallel — killing a worker as it starts', () => {
	it("never reaches the parent's SIGTERM handler", () => {
		// Killed right after the fork, a worker can relay the signal to the
		// parent's uloop handler until it has reset its own (the LSP then shut
		// down mid-scan). kill() waits for the worker to be ready instead.
		uloop.init();
		let relayed = 0, rounds = 0, completed = 0;
		let sig = uloop.signal('SIGTERM', () => { relayed++; });
		function round() {
			if (rounds++ >= 30) { uloop.end(); return; }
			let tasks = fanOut([0], 1,
				(x) => { for (let i = 0; i < 1000000000; i++); return x; },
				(_) => null,
				()  => { completed++; uloop.timer(1, round); });
			tasks[0].kill();
		}
		uloop.timer(1, round);
		let timeout = uloop.timer(60000, () => uloop.end());
		uloop.run();
		if (timeout) timeout.cancel();
		if (sig) sig.delete();
		assert.match(0, relayed);
		assert.match(30, completed);
	});
});

describe('parallel — jobsFor', () => {
	it('counts the CPUs in the affinity mask, not every host CPU', () => {
		let cpuinfo = join('', map(nums(16), (i) => sprintf('processor\t: %d\n', i)));
		assert.match(3, jobsFor('Name:\tucode\nCpus_allowed_list:\t0-2\n', 'max 100000', cpuinfo));
	});

	it('honours a fractional CPU quota, rounding up', () => {
		assert.match(2, jobsFor('Cpus_allowed_list:\t0-15\n', '150000 100000', null));
	});

	it('takes the smaller of the affinity mask and the quota', () => {
		assert.match(2, jobsFor('Cpus_allowed_list:\t0-7\n', '200000 100000', null));
		assert.match(3, jobsFor('Cpus_allowed_list:\t0-2\n', '800000 100000', null));
	});

	it('parses lists with single CPUs and ranges', () => {
		assert.match(7, jobsFor('Cpus_allowed_list:\t0-3,8,10-11\n', null, null));
	});

	it('falls back to /proc/cpuinfo, then to 1', () => {
		assert.match(4, jobsFor(null, null, 'processor\t: 0\nprocessor\t: 1\nprocessor\t: 2\nprocessor\t: 3\n'));
		assert.match(1, jobsFor(null, null, null));
	});

	it('caps the count at 8', () => {
		assert.match(8, jobsFor('Cpus_allowed_list:\t0-31\n', 'max 100000', null));
	});
});
