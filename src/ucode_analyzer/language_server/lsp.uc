import * as protocol from 'ucode_analyzer.language_server.protocol';
import * as uloop from 'uloop';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { hover as hoverDoc } from 'ucode_analyzer.language_server.handlers.hover';
import { definition as definitionDoc } from 'ucode_analyzer.language_server.handlers.definition';
import { completion as completionDoc } from 'ucode_analyzer.language_server.handlers.completion';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as workspace from 'ucode_analyzer.code_analysis.workspace';
import { invalidateUri } from 'ucode_analyzer.code_analysis.memo';
import { documentDiagnosticsPlan, workspaceDiagnostics, invalidate as invalidateDiagnostics, cancel as cancelWorkspaceDiagnostics, cancelRequest as cancelWorkspaceRequest } from 'ucode_analyzer.language_server.handlers.diagnostic_reports';
import { signatureHelp as signatureHelpDoc } from 'ucode_analyzer.language_server.handlers.signature_help';
import { referencesPlan } from 'ucode_analyzer.language_server.handlers.references';
import { documentSymbols as documentSymbolsDoc } from 'ucode_analyzer.language_server.handlers.document_symbols';
import { workspaceSymbol as workspaceSymbolDoc } from 'ucode_analyzer.language_server.handlers.workspace_symbol';
import { inlayHints as inlayHintsDoc } from 'ucode_analyzer.language_server.handlers.inlay_hints';
import { foldingRanges as foldingRangesDoc } from 'ucode_analyzer.language_server.handlers.folding_range';
import { renamePlan } from 'ucode_analyzer.language_server.handlers.rename';
import { documentHighlight as documentHighlightDoc } from 'ucode_analyzer.language_server.handlers.document_highlight';
import { prepareRename as prepareRenameDoc } from 'ucode_analyzer.language_server.handlers.prepare_rename';
import { codeAction as codeActionDoc } from 'ucode_analyzer.language_server.handlers.code_actions';
import { selectionRanges as selectionRangesDoc } from 'ucode_analyzer.language_server.handlers.selection_range';
import { linkedEditingRanges } from 'ucode_analyzer.language_server.handlers.linked_editing';
import { documentLinks } from 'ucode_analyzer.language_server.handlers.document_link';
import { prepareCallHierarchy as prepareCallHierarchyDoc, incomingCallsPlan, outgoingCalls as outgoingCallsDoc } from 'ucode_analyzer.language_server.handlers.call_hierarchy';
import * as platform from 'ucode_analyzer.language_server.platform';
import * as background from 'ucode_analyzer.language_server.background';
import { newProgress } from 'ucode_analyzer.language_server.progress';
import { FileChangeType } from 'ucode_analyzer.code_analysis.lsp_types';
import { detectJobs } from 'ucode_analyzer.code_analysis.parallel';

// How long a diagnostic refresh waits for further changes, in ms.
const REFRESH_DELAY = 500;

// Requests a partial index would answer wrongly rather than incompletely
// (false diagnostics, a rename missing importers): held until the startup
// load finishes.
const WAITS_FOR_INDEX = {
	'textDocument/diagnostic':     true,
	'workspace/diagnostic':        true,
	'textDocument/references':     true,
	'textDocument/rename':         true,
	'callHierarchy/incomingCalls': true,
	'workspace/symbol':            true,
};

// Drop everything derived from the files that import a changed file: type
// caches, diagnostics and, for open ones, scope maps.
function invalidateDependents(uris) {
	for (let uri in uris) {
		background.supersede(uri);
		invalidateUri(uri);
		invalidateDiagnostics(uri);
		documents.markStale(uri);
	}
}

// Index an opened or edited document into the DAG. Returns the files whose
// view of it changed, already invalidated.
function reindex(doc) {
	background.supersede(doc.uri);
	invalidateDiagnostics(doc.uri);
	let cascaded = dag.update(doc.uri, doc.text, doc.tree, documents.all());
	invalidateDependents(cascaded);
	return cascaded;
}

export function run(config) {
	documents.checkIncremental(config.debug?.checkIncremental === true);
	let shutdown_requested = false;
	let initialized = false;

	let clientCapabilities = {};

	// The client's responses to our requests that need one: id → callback.
	let awaiting = {};

	function requestThen(id, method, params, onResponse) {
		awaiting[id] = onResponse;
		protocol.request(id, method, params);
	}

	// The startup load: whether it runs, its workers and the requests it holds.
	let indexing = false;
	let loading = null;
	let held = [];

	function stopLoading() {
		if (loading) loading.kill();
		loading = null;
		indexing = false;
	}

	// Kill any in-flight background tasks before the process exits so their forked
	// children are not orphaned (reparented to init) and left burning CPU/memory.
	function teardown() {
		stopLoading();
		background.cancelAll();
		platform.cancel();
		cancelWorkspaceDiagnostics();
	}

	let dispatch;

	// Run the held requests: after the load, or rejected after shutdown.
	function release() {
		let msgs = held;
		held = [];
		for (let msg in msgs) dispatch(msg);
	}

	let _refreshSeq = 0;
	let _refreshTimer = null;

	// Ask pull-model clients to re-request diagnostics. Sent when a change can
	// affect files other than the one being edited (cross-file dependencies,
	// on-disk changes); the edited document itself is re-pulled by the client
	// automatically. Fire-and-forget: the client's empty response is ignored.
	// Debounced, since each refresh can start a workspace scan: while changes
	// keep coming (typing in a file others import), only the last one asks,
	// REFRESH_DELAY ms after it.
	let requestDiagnosticRefresh = function() {
		if (_refreshTimer) {
			_refreshTimer.set(REFRESH_DELAY);
			return;
		}
		_refreshTimer = uloop.timer(REFRESH_DELAY, function() {
			_refreshTimer = null;
			if (!shutdown_requested)
				protocol.request(sprintf('diag-refresh-%d', ++_refreshSeq),
					'workspace/diagnostic/refresh', null);
		});
	};

	const handlers = {
		initialize: function(msg) {
			clientCapabilities = msg.params?.capabilities ?? {};
			protocol.respond(msg.id, {
				capabilities: {
					textDocumentSync: 1,
					hoverProvider: true,
					definitionProvider: true,
					completionProvider: { triggerCharacters: ['.'] },
					signatureHelpProvider: { triggerCharacters: ['(', ','] },
					referencesProvider: true,
					documentSymbolProvider: true,
					documentHighlightProvider: true,
					renameProvider: { prepareProvider: true },
					codeActionProvider: { codeActionKinds: ['quickfix', 'refactor.rewrite'] },
					workspaceSymbolProvider: true,
					inlayHintProvider: true,
					foldingRangeProvider: true,
					selectionRangeProvider: true,
					linkedEditingRangeProvider: true,
					documentLinkProvider: { resolveProvider: false },
					callHierarchyProvider: true,
					diagnosticProvider: {
						interFileDependencies: true,
						workspaceDiagnostics: true,
					},
				},
				serverInfo: { name: 'ucode-analyzer', version: '0.1.0' },
			});
		},

		initialized: function(msg) {
			initialized = true;

			// Indexing takes seconds on a slow device: workers do it while the
			// loop keeps answering, and the editor shows how far it got.
			let progress = null;
			if (clientCapabilities.window?.workDoneProgress) {
				let token = 'ucode-analyzer/indexing';
				progress = newProgress(token, 'Indexing');
				requestThen('index-progress', 'window/workDoneProgress/create', { token },
					(resp) => progress.accepted(resp.error === null));
			}

			indexing = true;
			let load = workspace.loadWorkspaceAsync(config, detectJobs(), function(declVersions) {
				if (!indexing) return;
				indexing = false;
				loading = null;
				if (progress) progress.end(sprintf('%d files', length(dag.allUris())));
				// What was answered meanwhile came from a partial index.
				invalidateDependents(keys(documents.all()));
				// Package-manager queries are blocking subprocess calls; run them in a
				// background task. Availability only shows in hover and completion,
				// which read it when asked, so nothing needs refreshing when it lands.
				platform.initAsync(declVersions, null);
				release();
			}, function(done, total) {
				if (progress) progress.report(done, total);
			});
			if (indexing) loading = load;

			// Ask the editor to notify us when .uc files change on disk.
			protocol.request('cap-watch-uc', 'client/registerCapability', {
				registrations: [{
					id: 'cap-watch-uc',
					method: 'workspace/didChangeWatchedFiles',
					registerOptions: { watchers: [{ globPattern: '**/*.uc' }] },
				}],
			});
		},

		shutdown: function(msg) {
			shutdown_requested = true;
			stopLoading();
			release();
			protocol.respond(msg.id, null);
		},

		exit: function(msg) {
			uloop.end();
		},

		// Only held requests, plans in workers and the workspace scan wait; a
		// queued request is cancelled when its batch is read (see the dispatch
		// below), and others have already been answered.
		'$/cancelRequest': function(msg) {
			let id = msg.params?.id ?? null;
			let rest = filter(held, (m) => m.id !== id);
			if (length(rest) < length(held)) {
				held = rest;
				protocol.error(id, protocol.ErrorCode.REQUEST_CANCELLED, 'request cancelled');
				return;
			}
			if (!background.cancel(id))
				cancelWorkspaceRequest(id);
		},

		'textDocument/didOpen': function(msg) {
			let td = msg.params.textDocument;
			let doc = documents.open(td.uri, td.text, td.version);
			dag.markOpen(td.uri);
			reindex(doc);
			// Diagnostics are pulled: the client requests textDocument/diagnostic
			// for the freshly opened file on its own.
		},

		'textDocument/didChange': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version);
			if (!doc) return;
			// Document state is updated synchronously so hover/completion see fresh
			// state; the client re-pulls this document's diagnostics itself. If the
			// edit affected dependents, prompt a re-pull of everything.
			if (length(reindex(doc)) > 0)
				requestDiagnosticRefresh();
		},

		'textDocument/didClose': function(msg) {
			let uri = msg.params.textDocument.uri;
			background.supersede(uri);
			documents.close(uri);
			dag.markClosed(uri);
			// No publish: pull-model clients clear diagnostics for closed files.
		},

		'textDocument/diagnostic': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.peek(uri);
			if (!doc)
				return protocol.respond(msg.id, { kind: 'full', items: [] });
			background.respond(msg.id, documentDiagnosticsPlan(uri, doc, msg.params.previousResultId));
		},

		'workspace/diagnostic': function(msg) {
			// Responds asynchronously when the background scan finishes.
			workspaceDiagnostics(msg.id, msg.params, config);
		},

		'textDocument/hover': function(msg) {
			let doc = documents.get(msg.params.textDocument.uri);
			protocol.respond(msg.id, doc ? hoverDoc(doc, msg.params.position, config) : null);
		},

		'textDocument/definition': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? definitionDoc(uri, doc, msg.params.position) : null);
		},

		'textDocument/completion': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? completionDoc(uri, doc, msg.params.position) : []);
		},

		'textDocument/signatureHelp': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? signatureHelpDoc(uri, doc, msg.params.position) : null);
		},

		'textDocument/references': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			let ctx = msg.params.context;
			let includeDecl = (ctx && ctx.includeDeclaration === false) ? false : true;
			background.respond(msg.id, doc ? referencesPlan(uri, doc, msg.params.position, includeDecl) : null);
		},

		'textDocument/documentSymbol': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? documentSymbolsDoc(doc) : null);
		},

		'workspace/symbol': function(msg) {
			protocol.respond(msg.id, workspaceSymbolDoc(msg.params.query));
		},

		'textDocument/inlayHint': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? inlayHintsDoc(doc, msg.params.range) : null);
		},

		'textDocument/foldingRange': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? foldingRangesDoc(doc) : null);
		},

		'textDocument/linkedEditingRange': function(msg) {
			let doc = documents.get(msg.params.textDocument.uri);
			protocol.respond(msg.id, doc ? linkedEditingRanges(doc, msg.params.position) : null);
		},

		'textDocument/documentLink': function(msg) {
			let doc = documents.get(msg.params.textDocument.uri);
			protocol.respond(msg.id, doc ? documentLinks(doc) : null);
		},

		'textDocument/selectionRange': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? selectionRangesDoc(doc, msg.params.positions) : null);
		},

		'workspace/didChangeWatchedFiles': function(msg) {
			let changed = false;
			for (let change in (msg.params.changes ?? [])) {
				let uri = change.uri;
				let deleted = change.type === FileChangeType.DELETED;
				// The editor's text of an open file wins over the disk's.
				if (!deleted && documents.isOpen(uri)) continue;
				let revDeps = dag.reverseDeps(uri);
				if (deleted)
					dag.remove(uri);
				else
					dag.addFromDisk(uri);
				// A new file can satisfy imports that resolved to nothing.
				if (change.type === FileChangeType.CREATED) push(revDeps, ...dag.resolveUnresolved());
				invalidateUri(uri);
				invalidateDiagnostics(uri);
				invalidateDependents(revDeps);
				changed = true;
			}
			// On-disk changes can affect any file's diagnostics; prompt re-pull.
			if (changed)
				requestDiagnosticRefresh();
		},

		'textDocument/rename': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			background.respond(msg.id, doc
				? renamePlan(uri, doc, msg.params.position, msg.params.newName)
				: null);
		},

		'textDocument/documentHighlight': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? documentHighlightDoc(uri, doc, msg.params.position)
				: null);
		},

		'textDocument/prepareRename': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? prepareRenameDoc(uri, doc, msg.params.position)
				: null);
		},

		'textDocument/prepareCallHierarchy': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? prepareCallHierarchyDoc(uri, doc, msg.params.position)
				: null);
		},

		'callHierarchy/incomingCalls': function(msg) {
			background.respond(msg.id, incomingCallsPlan(msg.params.item));
		},

		'callHierarchy/outgoingCalls': function(msg) {
			protocol.respond(msg.id, outgoingCallsDoc(msg.params.item));
		},

		'textDocument/codeAction': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			let ctx = msg.params.context;
			let diags = (ctx && ctx.diagnostics) ? ctx.diagnostics : [];
			protocol.respond(msg.id, doc ? codeActionDoc(uri, doc, diags, msg.params.range) : null);
		},
	};

	uloop.init();

	// An exception escaping any event-loop callback -- the stdin reader, a
	// background task's output callback (workspace scan, package queries), a
	// timer -- would otherwise end the whole process (ucode exits with 254).
	// Log it and keep serving. Request handlers below still turn their own
	// errors into JSON-RPC error responses.
	uloop.guard(function(e) {
		let at = e?.stacktrace?.[0];
		warn(sprintf('ucode-analyzer: uncaught error in an event-loop callback: %s%s\n',
			e?.message ?? e, at ? sprintf(' (%s:%d)', at.filename, at.line) : ''));
	});

	dispatch = function(msg) {
		// A response to one of our requests.
		if (!msg.method && 'id' in msg) {
			let onResponse = awaiting[msg.id];
			delete awaiting[msg.id];
			if (onResponse) onResponse(msg);
			return;
		}

		// After shutdown, reject all requests (notifications are silently ignored).
		if (shutdown_requested && msg.method !== 'exit') {
			if ('id' in msg && msg.method)
				protocol.error(msg.id, protocol.ErrorCode.INVALID_REQUEST, 'server is shutting down');
			return;
		}

		// Before initialized, only allow initialize / initialized / exit / $/cancel.
		if (!initialized && msg.method !== 'initialize' && msg.method !== 'initialized' &&
		    msg.method !== 'exit' && msg.method !== '$/cancelRequest') {
			if ('id' in msg && msg.method)
				protocol.error(msg.id, protocol.ErrorCode.SERVER_NOT_INITIALIZED, 'server not yet initialized');
			return;
		}

		if (indexing && WAITS_FOR_INDEX[msg.method]) {
			push(held, msg);
			return;
		}

		let handler = handlers[msg.method];

		if (handler) {
			try {
				handler(msg);
			} catch(e) {
				// Logged for notifications too: nothing else would report them.
				warn(sprintf('ucode-analyzer: %s failed: %s\n', msg.method, e));
				if ('id' in msg)
					protocol.error(msg.id, protocol.ErrorCode.INTERNAL_ERROR, sprintf('internal error: %s', e));
			}
		} else if ('id' in msg && msg.method) {
			// Only unknown *requests* (have both id and method) get MethodNotFound.
			protocol.error(msg.id, protocol.ErrorCode.METHOD_NOT_FOUND, sprintf('method not found: %s', msg.method));
		}
	};

	protocol.startListening(
		function(bodies) {
			let msgs = [];
			for (let body in bodies) {
				try {
					push(msgs, json(body));
				} catch(e) {
					protocol.error(null, protocol.ErrorCode.PARSE_ERROR, 'Parse error');
				}
			}

			// A request whose cancellation arrived in the same batch is answered
			// as cancelled without running.
			let cancelled = {};
			for (let msg in msgs)
				if (msg?.method === '$/cancelRequest' && msg.params?.id !== null)
					cancelled[msg.params.id] = true;

			for (let msg in msgs) {
				if (msg?.method && 'id' in msg && cancelled[msg.id])
					protocol.error(msg.id, protocol.ErrorCode.REQUEST_CANCELLED, 'request cancelled');
				else
					dispatch(msg);
			}
		},
		function() {
			// EOF on stdin: stop the loop; the code after uloop.run() tears down
			// and exits (cleanly if shutdown was requested). Never exit() inside
			// a loop callback: the uloop.guard handler above would receive it as
			// an ordinary error, drop the exit status and keep the loop running.
			uloop.end();
		}
	);

	uloop.signal('SIGTERM', function() { uloop.end(); });

	uloop.run();
	teardown();
	exit(shutdown_requested ? 0 : 1);
};
