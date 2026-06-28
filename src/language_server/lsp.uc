import * as protocol from 'language_server.protocol';
import * as documents from 'language_server.documents';
import { hover as hoverDoc } from 'language_server.handlers.hover';
import { definition as definitionDoc } from 'language_server.handlers.definition';
import { completion as completionDoc } from 'language_server.handlers.completion';
import * as glob from 'language_server.glob';
import * as dag from 'language_server.dag.dag';
import { invalidateUri } from 'language_server.memo';
import { diagnosticsFor } from 'language_server.handlers.diagnostics';
import { signatureHelp as signatureHelpDoc } from 'language_server.handlers.signature_help';
import { references as referencesDoc } from 'language_server.handlers.references';
import { documentSymbols as documentSymbolsDoc } from 'language_server.handlers.document_symbols';
import { rename as renameDoc } from 'language_server.handlers.rename';
import { initBuiltinsFromDag } from 'language_server.types.inferrer';
import * as platform from 'language_server.platform';

export function run(config) {
	let shutdown_requested = false;
	let initialized = false;

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
					renameProvider: true,
				},
				serverInfo: { name: 'ucode-language-server', version: '0.1.0' },
			});
		},

		initialized: function(msg) {
			initialized = true;
			let workspaceDir = config.workspaceDir ?? '/root/project';
			let ws = config.workspace ?? {};
			let libPaths = ws.libraryPaths ?? ['src'];

			dag.init(config);

			for (let relPath in libPaths) {
				let files = glob.scan(workspaceDir + '/' + relPath, ['**/*.uc'], []);
				for (let path in files)
					dag.addFromDisk('file://' + path);
			}

			if (config.selfSrcDir) {
				let files = glob.scan(config.selfSrcDir + '/declarations', ['**/*.uc'], []);
				for (let path in files)
					dag.addFromDisk('file://' + path);
			}

			for (let sysPath in (config.systemLibPaths ?? [])) {
				let files = glob.scan(sysPath, ['**/*.uc'], []);
				for (let path in files)
					dag.addFromDisk('file://' + path);
			}

			let stdlibUri = dag.resolveSpecifier('stdlib');
			if (stdlibUri) initBuiltinsFromDag(stdlibUri);

			let declVersions = {};
			for (let uri in dag.allUris()) {
				if (index(uri, '.d.uc') < 0) continue;
				let v = dag.versionsOf(uri);
				if (v) declVersions[uri] = v;
			}
			platform.init(declVersions);
		},

		shutdown: function(msg) {
			shutdown_requested = true;
			protocol.respond(msg.id, null);
		},

		exit: function(msg) {
			exit(shutdown_requested ? 0 : 1);
		},

		'textDocument/didOpen': function(msg) {
			let td = msg.params.textDocument;
			documents.open(td.uri, td.text, td.version);
			dag.markOpen(td.uri);
			let doc = documents.get(td.uri);
			invalidateUri(td.uri);
			let cascaded = dag.update(td.uri, doc.text, doc.tree);
			for (let dep in cascaded) invalidateUri(dep);
			protocol.notify('textDocument/publishDiagnostics', {
				uri: td.uri,
				version: doc.version,
				diagnostics: diagnosticsFor(td.uri, doc),
			});
		},

		'textDocument/didChange': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version);
			let doc = documents.get(uri);
			if (!doc) return;
			invalidateUri(uri);
			let cascaded = dag.update(uri, doc.text, doc.tree);
			for (let dep in cascaded) invalidateUri(dep);
			protocol.notify('textDocument/publishDiagnostics', {
				uri,
				version: doc.version,
				diagnostics: diagnosticsFor(uri, doc),
			});
		},

		'textDocument/didClose': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.close(uri);
			dag.markClosed(uri);
			protocol.notify('textDocument/publishDiagnostics', { uri, diagnostics: [] });
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

		'textDocument/rename': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc
				? renameDoc(uri, doc, msg.params.position, msg.params.newName)
				: null);
		},
	};

	while (true) {
		let msg = protocol.read_message();

		if (msg === null) {
			// EOF or unrecoverable read error — exit cleanly if shutdown was requested.
			exit(shutdown_requested ? 0 : 1);
		}

		// After shutdown, reject all requests (notifications are silently ignored).
		if (shutdown_requested && msg.method !== 'exit') {
			if ('id' in msg)
				protocol.error(msg.id, -32600, 'server is shutting down');
			continue;
		}

		// Before initialized, only allow initialize / initialized / exit / $/cancel.
		if (!initialized && msg.method !== 'initialize' && msg.method !== 'initialized' &&
		    msg.method !== 'exit' && msg.method !== '$/cancelRequest') {
			if ('id' in msg)
				protocol.error(msg.id, -32002, 'server not yet initialized');
			continue;
		}

		let handler = handlers[msg.method];

		if (handler) {
			try {
				handler(msg);
			} catch (e) {
				if ('id' in msg)
					protocol.error(msg.id, -32603, sprintf('internal error: %s', e));
			}
		} else if ('id' in msg) {
			protocol.error(msg.id, -32601, sprintf('method not found: %s', msg.method));
		}
	}
};
