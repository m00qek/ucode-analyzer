// `ucode-analyzer lint`: the linter, over files or a whole workspace.

import { docopt } from 'docopt';
import { load as loadConfig, init as initConfig } from 'ucode_analyzer.code_analysis.config';
import { run } from 'ucode_analyzer.linter.run';
import { detectJobs } from 'ucode_analyzer.code_analysis.parallel';
import * as fs from 'fs';

const doc = `
ucode-analyzer lint - lint ucode source files.

Usage:
  ucode-analyzer lint [options] <file>...
  ucode-analyzer lint [options] --workspace=<path>
  ucode-analyzer lint --init [--workspace=<path>]
  ucode-analyzer lint -h | --help
  ucode-analyzer lint --version

Options:
  --workspace=<path>  Lint every .uc file in the workspace at <path>.
  --init              Write <workspace>/.lsp/config.json with the library paths
                      the linter and the language server would detect, to edit
                      by hand. The workspace defaults to the current directory.
  --config=<path>     Directory containing config.json. Defaults to the
                      workspace (file mode: the current directory).
  --format=<fmt>      Output format: text | json   [default: text]
  --fail-on=<sev>     Minimum severity that exits non-zero:
                      error | warning | info | hint | none   [default: error]
  --jobs=<n>          Parallel worker processes for workspace mode.
                      Defaults to the number of CPUs (capped at 8); 1 disables
                      forking.
  -h --help           Show this screen.
  --version           Show version.
`;

// pkgDir: the installed ucode_analyzer directory, holding the bundled
// declarations. Returns the exit status.
export function main(argv, pkgDir) {
	let args = docopt(doc, argv, true, '0.1.0');

	let files    = args['<file>'] ?? [];
	let fileMode = length(files) > 0;

	if (args['--init']) {
		let dir = fs.realpath(args['--workspace'] ?? fs.getcwd() ?? '.');
		let r = initConfig(dir);
		print(r.created ? sprintf('Wrote %s\n', r.path) : sprintf('%s already exists; left unchanged\n', r.path));
		return 0;
	}

	// In file mode the workspace root is the current directory (the imports in
	// the linted files resolve against it); otherwise it is the --workspace path.
	let workspaceDir = fileMode ? (fs.getcwd() ?? '.') : args['--workspace'];
	workspaceDir = fs.realpath(workspaceDir) ?? workspaceDir;

	let configDir = args['--config'] ?? workspaceDir;

	let config = loadConfig(configDir, workspaceDir);
	config.workspaceDir = workspaceDir;
	config.configDir    = configDir;
	config.selfSrcDir   = pkgDir;

	let jobs = args['--jobs'] ? (+args['--jobs'] || 1) : detectJobs();

	return run(config, {
		files:  fileMode ? files : null,
		format: args['--format'],
		failOn: args['--fail-on'],
		jobs:   (jobs < 1) ? 1 : jobs,
	});
};
