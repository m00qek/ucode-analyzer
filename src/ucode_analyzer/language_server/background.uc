// Requests whose cost grows with the workspace (references to a widely
// imported export, a rename, incoming calls) run as a plan, { items, work,
// finish }: their answer is finish(map(items, work)), one item per file. A
// large plan's work runs in forked workers, so the loop keeps answering; the
// request is answered when they finish, or cancelled.

import * as protocol from 'ucode_analyzer.language_server.protocol';
import { fanOut, detectJobs } from 'ucode_analyzer.code_analysis.parallel';

// Up to this many items a plan runs in-process: forking costs more.
const INLINE_MAX = 16;

let _running = {};   // request id → { tasks, cancelled }

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
	if (length(plan.items) <= INLINE_MAX)
		return protocol.respond(id, plan.finish(map(plan.items, plan.work)));

	// Results arrive in any order: each carries its item's index. An item
	// whose work threw (logged by fanOut) leaves a null.
	let results = map(plan.items, () => null);
	let job = { tasks: [], cancelled: false };
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

// Stop the workers of request `id` and answer it as cancelled. False when it
// is not running.
export function cancel(id) {
	let job = _running[id];
	if (!job) return false;
	job.cancelled = true;
	for (let t in job.tasks) t.kill();
	delete _running[id];
	protocol.error(id, protocol.ErrorCode.REQUEST_CANCELLED, 'request cancelled');
	return true;
};

// Stop every running plan, unanswered: the server is going away.
export function cancelAll() {
	for (let id, job in _running) {
		job.cancelled = true;
		for (let t in job.tasks) t.kill();
	}
	_running = {};
};
