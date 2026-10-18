// Requests whose cost grows with the workspace (references to a widely
// imported export, a rename, incoming calls) or with a large file (its
// diagnostics) run as a plan, { items, work, finish }: their answer is
// finish(map(items, work)), one item per file. A large plan's work runs in
// forked workers, so the loop keeps answering; the request is answered when
// they finish, or cancelled. A plan may also say whether it is small
// (`inline`), and carry a `key` (a document) whose change supersedes it.

import * as protocol from 'ucode_analyzer.language_server.protocol';
import { fanOut, detectJobs } from 'ucode_analyzer.code_analysis.parallel';

// Up to this many items a plan runs in-process: forking costs more.
const INLINE_MAX = 16;

let _running = {};   // request id → { id, key, tasks, cancelled }

function answer(id, plan, results) {
	let result;
	try {
		result = plan.finish(results);
	} catch (e) {
		warn(sprintf('ucode-analyzer: request %J failed: %s\n', id, e));
		return protocol.error(id, protocol.ErrorCode.INTERNAL_ERROR, sprintf('internal error: %s', e));
	}
	protocol.respond(id, result);
}

// Answer request `id` with what `plan` computes (null: answer null). `jobs`
// defaults to detectJobs().
export function respond(id, plan, jobs) {
	if (!plan) return protocol.respond(id, null);
	if (plan.inline ?? (length(plan.items) <= INLINE_MAX))
		return protocol.respond(id, plan.finish(map(plan.items, plan.work)));

	// Results arrive in any order: each carries its item's index. An item
	// whose work threw (logged by fanOut) leaves a null.
	let results = map(plan.items, () => null);
	let job = { id, key: plan.key, tasks: [], cancelled: false };
	_running[id] = job;
	let tasks = fanOut(map(plan.items, (item, i) => [i, item]), jobs ?? detectJobs(),
		(it) => [it[0], plan.work(it[1])],
		(r) => { results[r[0]] = r[1]; },
		() => {
			if (job.cancelled) return;
			delete _running[id];
			answer(id, plan, results);
		});
	job.tasks = tasks;
};

function stop(id) {
	let job = _running[id];
	job.cancelled = true;
	for (let t in job.tasks) t.kill();
	delete _running[id];
}

// Stop the workers of request `id` and answer it as cancelled. False when it
// is not running.
export function cancel(id) {
	if (!_running[id]) return false;
	stop(id);
	protocol.error(id, protocol.ErrorCode.REQUEST_CANCELLED, 'request cancelled');
	return true;
};

// Stop the plans keyed by `key`, whose document changed, and answer them as
// ContentModified: the client asks again for the new content.
export function supersede(key) {
	for (let k in keys(_running)) {
		let job = _running[k];
		if (job.key !== key) continue;
		stop(job.id);
		protocol.error(job.id, protocol.ErrorCode.CONTENT_MODIFIED, 'content modified');
	}
};

// Stop every running plan, unanswered: the server is going away.
export function cancelAll() {
	for (let id, job in _running) {
		job.cancelled = true;
		for (let t in job.tasks) t.kill();
	}
	_running = {};
};
