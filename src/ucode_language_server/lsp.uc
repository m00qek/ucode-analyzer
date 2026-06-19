import * as protocol from 'ucode_language_server.protocol';

let shutdown_requested = false;

const handlers = {
	initialize: function(msg) {
		protocol.respond(msg.id, {
			capabilities: {},
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
};

while (true) {
	let msg = protocol.read_message();

	if (msg == null)
		exit(shutdown_requested ? 0 : 1);

	let handler = handlers[msg.method];

	if (handler) {
		handler(msg);
	} else if ('id' in msg) {
		protocol.error(msg.id, -32601, sprintf('method not found: %s', msg.method));
	}
}
