#!/usr/bin/ucode
'use strict';

import { docopt } from 'docopt';
import { load as loadConfig } from 'code_analysis.config';
import { run } from 'linter.run';
import { detectJobs } from 'code_analysis.parallel';
import * as fs from 'fs';

const doc = `
ucode-linter - lint ucode source files.

Usage:
  ucode-linter [options] <file>...
  ucode-linter [options] --workspace=<path>
  ucode-linter -h | --help
  ucode-linter --version

Options:
  --workspace=<path>  Lint every .uc file in the workspace at <path>.
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

const args = docopt(doc, ARGV, true, '0.1.0');

const files    = args['<file>'] ?? [];
const fileMode = length(files) > 0;

// In file mode the workspace root is the current directory (the imports in the
// linted files resolve against it); otherwise it is the --workspace path.
let workspaceDir = fileMode ? (fs.getcwd() ?? '.') : args['--workspace'];
workspaceDir = fs.realpath(workspaceDir) ?? workspaceDir;

const configDir = args['--config'] ?? workspaceDir;

const config = loadConfig(configDir, workspaceDir);
config.workspaceDir = workspaceDir;
config.configDir    = configDir;

// Derive this script's directory so the analysis stack can fall back to the
// bundled stdlib declarations (mirrors ucode-language-server.uc).
const selfDir = sourcepath(0, true);
if (selfDir)
	config.selfSrcDir = selfDir;

const jobs = args['--jobs'] ? (+args['--jobs'] || 1) : detectJobs();

exit(run(config, {
	files:  fileMode ? files : null,
	format: args['--format'],
	failOn: args['--fail-on'],
	jobs:   (jobs < 1) ? 1 : jobs,
}));
