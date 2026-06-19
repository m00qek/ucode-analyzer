import { describe, it, assert } from 'utest';
import { spawn } from 'spawn_pipes';

describe('spawn_pipes', () => {
	it('echos a line back via cat', () => {
		let proc = spawn('cat', []);
		proc.write('hello\n');
		let out = proc.read(6);
		assert.match('hello\n', out);
		proc.close();
	});

	it('write() returns the byte count written', () => {
		let proc = spawn('cat', []);
		let n = proc.write('abc');
		assert.match(3, n);
		proc.close();
	});

	it('close() returns the child exit code', () => {
		let proc = spawn('true', []);
		assert.match(0, proc.close());
	});

	it('close() returns a negative signal code for signal-killed processes', () => {
		let proc = spawn('sh', ['-c', 'kill -KILL $$']);
		let code = proc.close();
		assert.match(true, code < 0);
	});

	it('read() returns empty string at EOF', () => {
		let proc = spawn('echo', ['hello']);
		proc.read(6);          /* consume "hello\n" */
		let eof = proc.read(1);
		assert.match('', eof);
		proc.close();
	});

	it('rejects non-string path', () => {
		assert.throws(() => { spawn(42, []); });
	});

	it('rejects non-array args', () => {
		assert.throws(() => { spawn('echo', 'bad'); });
	});
});
