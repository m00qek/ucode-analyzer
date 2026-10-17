import { describe, it, assert } from 'utest';
import * as client from 'client';

const ECHO = "import * as fs from \"fs\"; function r(n){let b=\"\";while(length(b)<n){let c=fs.stdin.read(n-length(b));if(!c||!length(c))exit(0);b+=c;}return b;} for(;;){let h=\"\";while(index(h,\"\\r\\n\\r\\n\")<0){let c=fs.stdin.read(1);if(!c||!length(c))exit(0);h+=c;}let m=match(h,/Content-Length: ([0-9]+)/);if(!m)exit(1);let b=r(+m[1]);fs.stdout.write(sprintf(\"Content-Length: %d\\r\\n\\r\\n%s\",length(b),b));fs.stdout.flush();}";

describe('rpc_client', () => {
	it('close() returns 0 for a clean exit', () => {
		let proc = client.spawn('true', []);
		assert.match(0, client.close(proc));
	});

	it('close() returns the exit status of a failed exit', () => {
		let proc = client.spawn('false', []);
		assert.match(1, client.close(proc));
	});

	it('close() returns a negative signal code', () => {
		let proc = client.spawn('sh', ['-c', 'kill -KILL $$']);
		assert.match(-9, client.close(proc));   // -SIGKILL
	});

	it('receive() returns null at EOF', () => {
		let proc = client.spawn('true', []);
		assert.match(null, client.receive(proc));
		client.close(proc);
	});

	it('send/receive round-trips a message', () => {
		let proc = client.spawn('ucode', ['-e', ECHO]);
		let msg = { jsonrpc: '2.0', id: 1, method: 'ping', params: {} };

		client.send(proc, msg);
		let resp = client.receive(proc);

		assert.match(1, resp.id);
		assert.match('ping', resp.method);

		client.close(proc);
	});
});
