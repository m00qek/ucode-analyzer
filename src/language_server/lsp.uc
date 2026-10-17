import * as protocol from 'language_server.protocol';
import * as uloop from 'uloop';
import * as documents from 'code_analysis.documents';
import { hover as hoverDoc } from 'language_server.handlers.hover';
import { definition as definitionDoc } from 'language_server.handlers.definition';
import { completion as completionDoc } from 'language_server.handlers.completion';
import * as dag from 'code_analysis.dag.dag';
import * as workspace from 'code_analysis.workspace';
import { invalidateUri } from 'code_analysis.memo';
import { documentDiagnostics, workspaceDiagnostics, invalidate as invalidateDiagnostics, cancel as cancelWorkspaceDiagnostics } from 'language_server.handlers.diagnostic_reports';
import { signatureHelp as signatureHelpDoc } from 'language_server.handlers.signature_help';
import { references as referencesDoc } from 'language_server.handlers.references';
import { documentSymbols as documentSymbolsDoc } from 'language_server.handlers.document_symbols';
import { workspaceSymbol as workspaceSymbolDoc } from 'language_server.handlers.workspace_symbol';
import { inlayHints as inlayHintsDoc } from 'language_server.handlers.inlay_hints';
import { foldingRanges as foldingRangesDoc } from 'language_server.handlers.folding_range';
import { rename as renameDoc } from 'language_server.handlers.rename';
import { documentHighlight as documentHighlightDoc } from 'language_server.handlers.document_highlight';
import { prepareRename as prepareRenameDoc } from 'language_server.handlers.prepare_rename';
import { codeAction as codeActionDoc } from 'language_server.handlers.code_actions';
import { selectionRanges as selectionRangesDoc } from 'language_server.handlers.selection_range';
import { linkedEditingRanges } from 'language_server.handlers.linked_editing';
import { documentLinks } from 'language_server.handlers.document_link';
import { prepareCallHierarchy as prepareCallHierarchyDoc, incomingCalls as incomingCallsDoc, outgoingCalls as outgoingCallsDoc } from 'language_server.handlers.call_hierarchy';
import * as platform from 'language_server.platform';

export function run(config) {
	let shutdown_requested = false;
	let initialized = false;

	// Kill any in-flight background tasks before the process exits so their forked
	// children are not orphaned (reparented to init) and left burning CPU/memory.
	function teardown() {
		platform.cancel();
		cancelWorkspaceDiagnostics();
	}

	let _refreshSeq = 0;

	// Ask pull-model clients to re-request diagnostics. Sent when a change can
	// affect files other than the one being edited (cross-file dependencies,
	// on-disk changes); the edited document itself is re-pulled by the client
	// automatically. Fire-and-forget: the client's empty response is ignored.
	let requestDiagnosticRefresh = function() {
		protocol.request(sprintf('diag-refresh-%d', ++_refreshSeq),
			'workspace/diagnostic/refresh', null);
	};

	const handlers = {
		initialize: function(msg) {
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
				serverInfo: { name: 'ucode-language-server', version: '0.1.0' },
			});
		},

		initialized: function(msg) {
			initialized = true;

			let declVersions = workspace.loadWorkspace(config);

			// Package-manager queries are blocking subprocess calls; run them in a
			// background task and refresh diagnostics once availability is known.
			platform.initAsync(declVersions, requestDiagnosticRefresh);

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
			protocol.respond(msg.id, null);
		},

		exit: function(msg) {
			uloop.end();
		},

		'textDocument/didOpen': function(msg) {
			let td = msg.params.textDocument;
			documents.open(td.uri, td.text, td.version, true);
			dag.markOpen(td.uri);
			let doc = documents.get(td.uri);
			invalidateUri(td.uri);
			invalidateDiagnostics(td.uri);
			let cascaded = dag.update(td.uri, doc.text, doc.tree, documents.all());
			for (let dep in cascaded) { invalidateUri(dep); invalidateDiagnostics(dep); }
			documents.refreshScopeMap(td.uri);
			// Diagnostics are pulled: the client requests textDocument/diagnostic
			// for the freshly opened file on its own.
		},

		'textDocument/didChange': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version, true);
			let doc = documents.get(uri);
			if (!doc) return;
			invalidateUri(uri);
			invalidateDiagnostics(uri);
			let cascaded = dag.update(uri, doc.text, doc.tree, documents.all());
			for (let dep in cascaded) { invalidateUri(dep); invalidateDiagnostics(dep); }
			documents.refreshScopeMap(uri);
			// Document state is updated synchronously so hover/completion see fresh
			// state; the client re-pulls this document's diagnostics itself. If the
			// edit affected dependents, prompt a re-pull of everything.
			if (length(cascaded) > 0)
				requestDiagnosticRefresh();
		},

		'textDocument/didClose': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.close(uri);
			dag.markClosed(uri);
			// No publish: pull-model clients clear diagnostics for closed files.
		},

		'textDocument/diagnostic': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? documentDiagnostics(uri, doc, msg.params.previousResultId)
				: { kind: 'full', items: [] });
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
			protocol.respond(msg.id, doc ? referencesDoc(uri, doc, msg.params.position, includeDecl) : null);
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
				if (change.type === 3) {  // deleted
					let revDeps = dag.reverseDeps(uri);
					dag.remove(uri);
					invalidateUri(uri);
					invalidateDiagnostics(uri);
					for (let dep in revDeps) { invalidateUri(dep); invalidateDiagnostics(dep); }
					changed = true;
				} else if (!documents.get(uri)) {  // created (1) or changed (2), not open in editor
					let revDeps = dag.reverseDeps(uri);
					dag.addFromDisk(uri);
					invalidateUri(uri);
					invalidateDiagnostics(uri);
					for (let dep in revDeps) { invalidateUri(dep); invalidateDiagnostics(dep); }
					changed = true;
				}
			}
			// On-disk changes can affect any file's diagnostics; prompt re-pull.
			if (changed)
				requestDiagnosticRefresh();
		},

		'textDocument/rename': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? renameDoc(uri, doc, msg.params.position, msg.params.newName)
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
			protocol.respond(msg.id, incomingCallsDoc(msg.params.item));
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
		warn(sprintf('ucode-ls: uncaught error in an event-loop callback: %s%s\n',
			e?.message ?? e, at ? sprintf(' (%s:%d)', at.filename, at.line) : ''));
	});

	protocol.startListening(
		function(body) {
			let msg;
			try {
				msg = json(body);
			} catch(e) {
				protocol.error(null, -32700, 'Parse error');
				return;
			}

			// After shutdown, reject all requests (notifications are silently ignored).
			// Response messages (no method) are also silently ignored.
			if (shutdown_requested && msg.method !== 'exit') {
				if ('id' in msg && msg.method)
					protocol.error(msg.id, -32600, 'server is shutting down');
				return;
			}

			// Before initialized, only allow initialize / initialized / exit / $/cancel.
			// Response messages (no method) are silently ignored.
			if (!initialized && msg.method !== 'initialize' && msg.method !== 'initialized' &&
			    msg.method !== 'exit' && msg.method !== '$/cancelRequest') {
				if ('id' in msg && msg.method)
					protocol.error(msg.id, -32002, 'server not yet initialized');
				return;
			}

			let handler = handlers[msg.method];

			if (handler) {
				try {
					handler(msg);
				} catch(e) {
					if ('id' in msg)
						protocol.error(msg.id, -32603, sprintf('internal error: %s', e));
				}
			} else if ('id' in msg && msg.method) {
				// Only unknown *requests* (have both id and method) get MethodNotFound.
				// Response messages (client replies to our outbound requests) have id but
				// no method — ignore them silently.
				protocol.error(msg.id, -32601, sprintf('method not found: %s', msg.method));
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
