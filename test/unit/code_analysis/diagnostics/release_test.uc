import { describe, it, assert, afterEach } from 'utest';
import * as documents from 'ucode_analyzer.code_analysis.documents';
import * as dag from 'ucode_analyzer.code_analysis.dag.dag';
import * as releases from 'ucode_analyzer.code_analysis.releases';
import { initBuiltinsFromDag } from 'ucode_analyzer.code_analysis.types.dag_bridge';
import { releaseChecks } from 'ucode_analyzer.code_analysis.diagnostics.release';
import { cursors } from 'cursor';
import * as fixture from 'fixture';

let URI = fixture.uri('test_release.uc');

dag.init(fixture.config());
let _g = dag.resolveSpecifier('global');
dag.addFromDisk(_g);
initBuiltinsFromDag(_g);
for (let m in [ 'fs', 'uci', 'socket' ]) dag.addFromDisk(dag.resolveSpecifier(m));

afterEach(() => {
	releases.setTarget(null);
	documents.close(URI);
	dag.remove(URI);
});

// The not-in-release messages for text with target `release`.
function messages(release, text) {
	releases.setTarget(release);
	documents.open(URI, text, 1);
	dag.add(URI, text, documents.peek(URI).tree);   // before the scope map, which resolves imports
	return map(releaseChecks(URI, documents.get(URI)), (d) => d.message);
}

describe('diagnostics — code the target release cannot run', () => {
	it('checks nothing without a target', () => {
		assert.match([], messages(null, "import * as socket from 'socket';\n"));
	});

	it('flags a module the release does not ship, at its name', () => {
		let src = cursors("import * as socket from $0'socket'$1;\n");
		releases.setTarget('23.05');
		documents.open(URI, src.text, 1);
		assert.match([{
			range: { start: src.at[0], end: src.at[1] }, severity: 2, source: 'ucode-analyzer',
			code: 'not-in-release', message: "Module 'socket' is not in OpenWrt 23.05: it came in 24.10",
		}], releaseChecks(URI, documents.get(URI)));
		assert.match([ "Module 'socket' is not in OpenWrt 23.05: it came in 24.10" ],
			messages('23.05', "let s = require('socket');\n"));
		assert.match([], messages('24.10', "import * as socket from 'socket';\n"));
	});

	it('flags module members added after the release', () => {
		assert.match([ "'fs.mkdtemp' is not in OpenWrt 24.10: it came in 25.12" ],
			messages('24.10', "import { pipe, mkdtemp } from 'fs';\n"));
		assert.match([ "'fs.dup2' is not in OpenWrt 24.10: it came in 25.12" ],
			messages('24.10', "import * as fs from 'fs';\nfs.dup2(1, 2);\nfs.pipe();\n"));
		assert.match([ "'fs.ST_RDONLY' is in no OpenWrt release, 25.12 included" ],
			messages('25.12', "import * as fs from 'fs';\nlet r = fs.ST_RDONLY;\n"));
		assert.match([], messages('main', "import * as fs from 'fs';\nlet r = fs.ST_RDONLY;\n"));
	});

	it('flags handle methods added after the release', () => {
		assert.match([ "'ioctl()' is not in OpenWrt 23.05: it came in 24.10" ],
			messages('23.05', "import * as fs from 'fs';\nlet f = fs.open('/x');\nf.isatty();\nf.ioctl(0, 0, 0);\n"));
		assert.match([ "'list_append()' is not in OpenWrt 23.05: it came in 24.10" ],
			messages('23.05', "import { cursor } from 'uci';\nlet c = cursor();\nc.list_append('a', 'b', 'c', 'd');\n"));
	});

	it('flags builtins added after the release, not a local of that name', () => {
		assert.match([ "'signal()' is not in OpenWrt 22.03: it came in 23.05" ], messages('22.03', "signal('SIGINT');\n"));
		assert.match([], messages('22.03', "function signal(s) {}\nsignal('SIGINT');\n"));
	});

	it('knows the releases it has data for', () => {
		assert.match(true, releases.setTarget('24.10'));
		assert.match(false, releases.setTarget('21.02'));
		assert.match(null, releases.target());
	});
});
