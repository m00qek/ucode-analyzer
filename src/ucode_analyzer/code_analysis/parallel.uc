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

function readText(path) {
	let f = fs.open(path, 'r');
	if (!f) return null;
	let text = f.read('all');
	f.close();
	return text;
}

// Count the CPUs in a Linux CPU list: "0-3,8,10-11" → 7.
function countCpuList(list) {
	let n = 0;
	for (let part in split(trim(list), ',')) {
		let m = match(part, /^([0-9]+)(-([0-9]+))?$/);
		if (m) n += m[3] ? int(m[3]) - int(m[1]) + 1 : 1;
	}
	return n;
}

// The worker count for the given contents of /proc/self/status, the cgroup CPU
// quota ("<quota> <period>", as in cgroup v2's cpu.max; "max …" = unlimited)
// and /proc/cpuinfo — any may be null. Pure, so the arithmetic is testable.
//
// Counts the CPUs this process may actually use: the affinity mask (a
// container's --cpuset-cpus) and the CPU quota (--cpus) both limit it, while
// /proc/cpuinfo lists every host CPU regardless; it is only the fallback.
// Capped at 8.
export function jobsFor(status, cpuMax, cpuinfo) {
	let n = 0;
	let allowed = status ? match(status, /Cpus_allowed_list:[ \t]*([0-9,-]+)/) : null;
	if (allowed)
		n = countCpuList(allowed[1]);
	if (n < 1 && cpuinfo)
		for (let line in split(cpuinfo, '\n'))
			if (match(line, /^processor[ \t]*:/)) n++;

	let quota = cpuMax ? match(cpuMax, /^([0-9]+)[ \t]+([0-9]+)/) : null;
	if (quota && int(quota[2]) > 0) {
		let limit = int((int(quota[1]) + int(quota[2]) - 1) / int(quota[2]));
		if (n < 1 || limit < n) n = limit;
	}

	if (n < 1) n = 1;
	return (n > 8) ? 8 : n;
};

// Default worker count for batch work. Batch workspace work is the one place
// the design permits scaling past the 2-core floor (see CLAUDE.md) — the
// interactive hot path never forks.
export function detectJobs() {
	// cgroup v2 exposes the quota as cpu.max; v1 as two files (-1 = unlimited).
	let cpuMax = readText('/sys/fs/cgroup/cpu.max');
	if (cpuMax === null) {
		let q = readText('/sys/fs/cgroup/cpu/cpu.cfs_quota_us');
		let p = readText('/sys/fs/cgroup/cpu/cpu.cfs_period_us');
		if (q !== null && p !== null && int(q) > 0)
			cpuMax = sprintf('%d %d', int(q), int(p));
	}
	return jobsFor(readText('/proc/self/status'), cpuMax, readText('/proc/cpuinfo'));
};

// Fan `items` out across up to `jobs` worker processes on the CURRENT event loop
// (the caller owns `uloop.init`/`run`/`end`; this function touches none of them).
//
//   work(item)   runs in the child; its return value (null included) is piped
//                back to the parent
//   onItem(res)  runs in the parent once per result
//   onDone()     runs in the parent exactly once, after every worker has finished
//
// A work(item) that throws is reported on stderr and skipped; its worker goes
// on with the rest of its shard. Returns the array of task handles so the
// caller can `kill()` them (e.g. to abort a superseded scan). `jobs` is clamped
// to `[1, length(items)]`. An empty `items` forks nothing and invokes `onDone()`
// immediately, so the caller's completion path fires uniformly regardless of
// workload size.
//
// Completion does not rely on uloop's implicit end-of-task message (the task
// function's return value, sent after it returns): a worker that dies without
// returning -- a crash in native code, a kill -- never sends it. Each worker
// sends an explicit `done` marker instead, and a watchdog also counts a worker
// as finished once its process has exited; uloop delivers everything the
// worker sent before it marks the task finished. Results are wrapped, so a null
// result cannot be mistaken for the end of a worker either.
//
// Each call owns its own completion state, so overlapping fan-outs (a new scan
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

	let shards    = shardRoundRobin(items, jobs);
	let tasks     = [];
	let finished  = [];
	let remaining = jobs;
	let watchdog  = null;

	function runItem(item) {
		try {
			return { result: work(item) };
		} catch (e) {
			return { error: e?.message ?? sprintf('%s', e) };
		}
	}

	function deliver(msg) {
		if (exists(msg, 'error'))
			warn(sprintf('ucode-analyzer: worker item failed: %s\n', msg.error));
		else
			onItem(msg.result);
	}

	function finish(s) {
		if (finished[s]) return;
		finished[s] = true;
		if (--remaining > 0) return;
		if (watchdog) {
			watchdog.cancel();
			watchdog = null;
		}
		onDone();
	}

	for (let s = 0; s < jobs; s++) {
		let idx   = s;
		let shard = shards[idx];
		let task  = uloop.task(
			function(pipe) {
				// The worker inherits the server's uloop SIGTERM handler, which
				// here only queues the signal for a loop that never runs: without
				// the default action, kill() leaves the worker running.
				signal('SIGTERM', 'default');
				for (let item in shard)
					pipe.send(runItem(item));
				pipe.send({ done: true });
			},
			function(msg) {
				// null: uloop's implicit end-of-task message, superseded by `done`.
				if (msg === null) return;
				if (msg.done) return finish(idx);
				deliver(msg);
			}
		);

		// Fork failed: do this shard here rather than lose it.
		if (!task) {
			warn('ucode-analyzer: could not fork a worker; running its shard in-process\n');
			for (let item in shard)
				deliver(runItem(item));
			finish(idx);
			continue;
		}
		tasks[idx] = task;
	}

	// A self-re-arming uloop.timer rather than uloop.interval: on the ucode we
	// target (OpenWrt 25.12), an interval that is cancelled and later
	// garbage-collected unregisters fd 0 from the event loop -- in the LSP that
	// is stdin, so the server silently stops receiving requests.
	if (remaining > 0) {
		watchdog = uloop.timer(250, function() {
			for (let s = 0; s < jobs; s++) {
				if (finished[s] || !tasks[s] || !tasks[s].finished()) continue;
				warn(sprintf('ucode-analyzer: worker %d exited before finishing its shard\n', s));
				finish(s);
			}
			// finish() cleared it if this tick completed the fan-out.
			if (watchdog) watchdog.set(250);
		});
	}

	return filter(tasks, (t) => t != null);
};
