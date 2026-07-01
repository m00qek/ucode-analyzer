import { describe, it, assert } from 'utest';
import { shardRoundRobin } from 'linter.run';

// [0, 1, …, n-1]
function nums(n) {
	let a = [];
	for (let i = 0; i < n; i++) push(a, i);
	return a;
}

describe('linter/run — shardRoundRobin', () => {
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
