import * as protocol from 'ucode_language_server.protocol';
import * as documents from 'ucode_language_server.documents';

let shutdown_requested = false;

const handlers = {
	initialize: function(msg) {
		protocol.respond(msg.id, {
			capabilities: {
				textDocumentSync: 1,
			},
			serverInfo: { name: 'ucode-language-server', version: '0.1.0' },
		});
	},

	initialized: function(msg) {
		// notification — no response
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
	},

	'textDocument/didChange': function(msg) {
		documents.change(
			msg.params.textDocument.uri,
			msg.params.contentChanges,
			msg.params.textDocument.version
		);
	},

	'textDocument/didClose': function(msg) {
		documents.close(msg.params.textDocument.uri);
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
