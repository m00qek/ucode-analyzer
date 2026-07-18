// Shared workspace-scan parallelism, used by both frontends: the CLI linter
// (which owns its event loop) and the LSP's background `workspace/diagnostic`
// scan (which runs inside the server's already-running event loop).
//
// The primitive here — `fanOut` — is deliberately LOOP-AGNOSTIC: it forks the
// workers with `uloop.task` on whatever event loop is already current and
// reports completion through a callback, never calling `uloop.init`/`run`/`end`
// itself. That is the whole reason the linter's parallel routine could not just
// be called from the LSP: the linter wraps its own `init`/`run` around the
// scan and blocks until it finishes, which is impossible inside the LSP's live
// loop. Splitting "fan out N tasks and count completions" from "own the loop"
// lets both callers share the machinery.

import * as uloop from 'uloop';
import * as fs from 'fs';

// Distribute `items` round-robin into `jobs` shards: shard s holds items
// s, s+jobs, s+2*jobs, … This spreads work evenly (sizes differ by at most one)
// and assigns every item to exactly one shard — a sharding bug would silently
// drop or double-process files. Exported so the shard math can be tested apart
// from the fork machinery.
export function shardRoundRobin(items, jobs) {
	let shards = [];
	for (let i = 0; i < jobs; i++) push(shards, []);
	for (let i = 0; i < length(items); i++)
		push(shards[i % jobs], items[i]);
	return shards;
};

// Number of online CPUs (Linux), capped, as the default worker count. Batch
// workspace work is the one place the design permits scaling past the 2-core
// floor (see CLAUDE.md) — the interactive hot path never forks.
export function detectJobs() {
	let f = fs.open('/proc/cpuinfo', 'r');
	if (!f) return 1;
	let text = f.read('all');
	f.close();
	let n = 0;
	for (let line in split(text, '\n'))
		if (match(line, /^processor[ \t]*:/)) n++;
	if (n < 1) n = 1;
	return (n > 8) ? 8 : n;
};

// Fan `items` out across up to `jobs` worker processes on the CURRENT event loop
// (the caller owns `uloop.init`/`run`/`end`; this function touches none of them).
//
//   work(item)   runs in the child; its return value is piped back to the parent
//   onItem(res)  runs in the parent once per result
//   onDone()     runs in the parent exactly once, after every worker's completion
//                sentinel has arrived
//
// Returns the array of task handles so the caller can `kill()` them (e.g. to
// abort a superseded scan). `jobs` is clamped to `[1, length(items)]`. An empty
// `items` forks nothing and invokes `onDone()` immediately, so the caller's
// completion path fires uniformly regardless of workload size.
//
// Each call owns its own completion counter, so overlapping fan-outs (a new scan
// started before an old one drains) never cross-count. Note `kill()` does not
// guarantee a child's already-queued pipe callbacks stop firing, so a caller
// that reuses shared state across scans must still guard `onItem`/`onDone`
// against a stale scan (the LSP does this with a generation number).
export function fanOut(items, jobs, work, onItem, onDone) {
	let n = length(items);
	if (n === 0) {
		onDone();
		return [];
	}
	if (jobs > n) jobs = n;
	if (jobs < 1) jobs = 1;

	let shards = shardRoundRobin(items, jobs);
	let tasks  = [];
	let done   = 0;
	for (let s = 0; s < jobs; s++) {
		let shard = shards[s];
		push(tasks, uloop.task(
			function(pipe) {
				for (let item in shard) pipe.send(work(item));
			},
			function(result) {
				// null is uloop's per-task completion sentinel.
				if (result === null) {
					if (++done === jobs) onDone();
					return;
				}
				onItem(result);
			}
		));
	}
	return tasks;
};
