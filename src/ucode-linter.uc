#!/usr/bin/ucode
'use strict';

import { docopt } from 'docopt';
import { load as loadConfig } from 'language_server.config';
import { run } from 'linter.run';
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
const selfPath = sourcepath();
if (selfPath) {
	const parts = split(selfPath, '/');
	pop(parts);
	config.selfSrcDir = join('/', parts) || '/';
}

exit(run(config, {
	files:  fileMode ? files : null,
	format: args['--format'],
	failOn: args['--fail-on'],
}));
