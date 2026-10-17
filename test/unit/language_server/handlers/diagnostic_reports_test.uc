import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import { documentDiagnostics, invalidate, cancelRequest } from 'ucode_analyzer.language_server.handlers.diagnostic_reports';

let URI = 'file:///reports.uc';

afterEach(() => documents.close(URI));

function open(text) {
	documents.open(URI, text, 1);
	return documents.get(URI);
}

describe('diagnostic_reports — textDocument/diagnostic', () => {
	it('answers unchanged while the previous resultId is current', () => {
		let doc = open('let unused = 1;\n');
		let first = documentDiagnostics(URI, doc, null);
		assert.match('full', first.kind);
		assert.match(['unused-var'], map(first.items, (d) => d.code));
		assert.match({ kind: 'unchanged', resultId: first.resultId }, documentDiagnostics(URI, doc, first.resultId));
	});

	it('answers in full after the document is invalidated', () => {
		let doc = open('let unused = 1;\n');
		let first = documentDiagnostics(URI, doc, null);
		invalidate(URI);
		let second = documentDiagnostics(URI, doc, first.resultId);
		assert.match('full', second.kind);
		assert.match(first.items, second.items);
		// resultIds are opaque: only a new one matters
		assert.match(true, second.resultId !== first.resultId);
	});

	it('keeps each document its own resultId', () => {
		let doc = open('let unused = 1;\n');
		let first = documentDiagnostics(URI, doc, null);
		invalidate('file:///other.uc');
		assert.match('unchanged', documentDiagnostics(URI, doc, first.resultId).kind);
	});
});

describe('diagnostic_reports — cancelRequest', () => {
	it('does nothing when no scan serves the request', () => {
		assert.match(false, cancelRequest(42));
		assert.match(false, cancelRequest(null));
	});
});
