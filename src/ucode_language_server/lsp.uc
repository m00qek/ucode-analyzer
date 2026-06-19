import * as protocol from 'ucode_language_server.protocol';
import * as documents from 'ucode_language_server.documents';
import { hover as hoverDoc } from 'ucode_language_server.hover';
import * as glob from 'ucode_language_server.glob';
import * as dag from 'ucode_language_server.dag';
import { invalidateUri } from 'ucode_language_server.memo';

export function run(config) {
	let shutdown_requested = false;

	const handlers = {
		initialize: function(msg) {
			protocol.respond(msg.id, {
				capabilities: {
					textDocumentSync: 1,
					hoverProvider: true,
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
		},

		'textDocument/didChange': function(msg) {
			let uri = msg.params.textDocument.uri;
			documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version);
			let doc = documents.get(uri);
			invalidateUri(uri);
			dag.update(uri, doc.text, doc.tree);
		},

		'textDocument/didClose': function(msg) {
			documents.close(msg.params.textDocument.uri);
		},

		'textDocument/hover': function(msg) {
			let doc = documents.get(msg.params.textDocument.uri);
			protocol.respond(msg.id, doc ? hoverDoc(doc, msg.params.position) : null);
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
