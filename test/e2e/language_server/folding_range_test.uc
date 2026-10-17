import { describe, it, assert, setup, teardown } from 'utest';
import * as lsp from 'client';
import { cursors } from 'cursor';

let proc;

setup(() => {
	proc = lsp.connect();
	lsp.initialize(proc);
});

teardown(() => {
	lsp.shutdown(proc);
	assert.match(0, lsp.close(proc));
});

describe('textDocument/foldingRange', () => {

	it('capability is advertised', () => {
		lsp.shutdown(proc);
		lsp.close(proc);
		proc = lsp.connect();
		let resp = lsp.initialize(proc);
		assert.match(true, resp.result.capabilities.foldingRangeProvider === true);
	});

	it('returns empty list for a file with no blocks', () => {
		lsp.open(proc, 'file:///t.uc', "let x = 1;\n");
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, resp.id);
		assert.match(0, length(resp.result));
	});

	it('returns a range for a multi-line function body', () => {
		let src = cursors("$1function foo() {\n  let x = 1;\n  return x;\n$2}\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		assert.match(1, length(resp.result));
		assert.match(src.at[1].line, resp.result[0].startLine);
		assert.match(src.at[2].line, resp.result[0].endLine);
	});

	it('emits an imports range for multiple consecutive imports', () => {
		let src = cursors("$1import * as a from 'utest';\n$2import * as b from 'utest';\n\nlet x = 1;\n");
		lsp.open(proc, 'file:///t.uc', src.text);
		lsp.send(proc, { jsonrpc: '2.0', id: 1, method: 'textDocument/foldingRange', params: {
			textDocument: { uri: 'file:///t.uc' },
		}});
		let resp = lsp.receive(proc);
		let imp = filter(resp.result, (r) => r.kind === 'imports')[0];
		assert.match(true, imp !== null);
		assert.match(src.at[1].line, imp.startLine);
		assert.match(src.at[2].line, imp.endLine);
	});
});
