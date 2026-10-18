// Work-done progress ($/progress) on a token the server created with
// window/workDoneProgress/create. Nothing is sent before the client accepts
// the token; accepted late, it still gets a begin and, if the work is over,
// the end.

import * as protocol from 'ucode_analyzer.language_server.protocol';

// Reports go out in steps of this many percent.
const STEP = 5;

// `notify` (default protocol.notify) sends a notification.
export function newProgress(token, title, notify) {
	notify ??= protocol.notify;
	let accepted = false, finished = false;
	let percentage = 0, message = null, sentAt = 0, endMessage = null;

	function send(value) {
		notify('$/progress', { token, value });
	}

	return {
		// The client's answer to the create request.
		accepted: function(ok) {
			if (!ok || accepted) return;
			accepted = true;
			send({ kind: 'begin', title, percentage, message, cancellable: false });
			sentAt = percentage;
			if (finished) send({ kind: 'end', message: endMessage });
		},

		report: function(done, total) {
			percentage = (total > 0) ? int(done * 100 / total) : 0;
			message = sprintf('%d/%d files', done, total);
			if (!accepted || finished || percentage < sentAt + STEP) return;
			sentAt = percentage;
			send({ kind: 'report', percentage, message });
		},

		end: function(msg) {
			if (finished) return;
			finished = true;
			endMessage = msg;
			if (accepted) send({ kind: 'end', message: msg });
		},
	};
};
