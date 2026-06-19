import * as protocol from 'ucode_language_server.protocol';
import * as documents from 'ucode_language_server.documents';
import { hover as hoverDoc } from 'ucode_language_server.hover';
import { definition as definitionDoc } from 'ucode_language_server.definition';
import { completion as completionDoc } from 'ucode_language_server.completion';
import * as glob from 'ucode_language_server.glob';
import * as dag from 'ucode_language_server.dag';
import { invalidateUri } from 'ucode_language_server.memo';
import { diagnosticsFor } from 'ucode_language_server.diagnostics';
import { signatureHelp as signatureHelpDoc } from 'ucode_language_server.signature_help';
import { references as referencesDoc } from 'ucode_language_server.references';
import { documentSymbols as documentSymbolsDoc } from 'ucode_language_server.document_symbols';

export function run(config) {
	let shutdown_requested = false;

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
				},
				serverInfo: { name: 'ucode-language-server', version: '0.1.0' },
			});
		},

		initialized: function(msg) {
			let workspaceDir = config.workspaceDir ?? '/root/project';
			let ws = config.workspace ?? {};
			let includes = ws.include ?? ['**/*.uc'];
			let excludes = ws.exclude ?? [];

			dag.init(config);

			let files = glob.scan(workspaceDir, includes, excludes);
			for (let path in files)
				dag.addFromDisk('file://' + path);
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
			let doc = documents.get(td.uri);
			invalidateUri(td.uri);
			dag.update(td.uri, doc.text, doc.tree);
			protocol.notify('textDocument/publishDiagnostics', {
				uri: td.uri,
				diagnostics: diagnosticsFor(td.uri, doc),
			});
		},

		'textDocument/didChange': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version);
			let doc = documents.get(uri);
			invalidateUri(uri);
			dag.update(uri, doc.text, doc.tree);
			protocol.notify('textDocument/publishDiagnostics', {
				uri,
				diagnostics: diagnosticsFor(uri, doc),
			});
		},

		'textDocument/didClose': function(msg) {
			documents.close(msg.params.textDocument.uri);
		},

		'textDocument/hover': function(msg) {
			let doc = documents.get(msg.params.textDocument.uri);
			protocol.respond(msg.id, doc ? hoverDoc(doc, msg.params.position) : null);
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
			protocol.respond(msg.id, doc ? referencesDoc(uri, doc, msg.params.position) : null);
		},

		'textDocument/documentSymbol': function(msg) {
			let uri = msg.params.textDocument.uri;
			let doc = documents.get(uri);
			protocol.respond(msg.id, doc ? documentSymbolsDoc(doc) : null);
		},
	};

	while (true) {
		let msg = protocol.read_message();

		if (msg === null)
			exit(shutdown_requested ? 0 : 1);

		let handler = handlers[msg.method];

		if (handler) {
			handler(msg);
		} else if ('id' in msg) {
			protocol.error(msg.id, -32601, sprintf('method not found: %s', msg.method));
		}
	}
};
