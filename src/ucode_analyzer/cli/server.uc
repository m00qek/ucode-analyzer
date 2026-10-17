// `ucode-analyzer [server]`: the language server, on stdin/stdout.

import { docopt } from 'docopt';
import { load as loadConfig } from 'ucode_analyzer.code_analysis.config';
import { run } from 'ucode_analyzer.language_server.lsp';

const doc = `
ucode-analyzer - language server and linter for ucode.

Usage:
  ucode-analyzer [server] --config=<path> --workspace=<path>
  ucode-analyzer -h | --help
  ucode-analyzer --version

Options:
  --config=<path>    Path to user config directory inside the container.
  --workspace=<path> Path to project root inside the container.
  -h --help          Show this screen.
  --version          Show version.

Run \`ucode-analyzer lint --help\` for the linter.
`;

// pkgDir: the installed ucode_analyzer directory, holding the bundled
// declarations and hover templates.
export function main(argv, pkgDir) {
	let args = docopt(doc, argv, true, '0.1.0');
	let config = loadConfig(args['--config'], args['--workspace']);
	config.workspaceDir = args['--workspace'];
	config.configDir    = args['--config'];
	config.selfSrcDir   = pkgDir;
	run(config);
};
