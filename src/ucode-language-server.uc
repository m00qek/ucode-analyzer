#!/usr/bin/ucode
'use strict';

import { docopt } from 'docopt';
import { load as loadConfig } from 'ucode_language_server.config';
import { run } from 'ucode_language_server.lsp';

const doc = `
ucode-language-server - LSP server for ucode.

Usage:
  ucode-language-server --config=<path> --workspace=<path>
  ucode-language-server -h | --help
  ucode-language-server --version

Options:
  --config=<path>    Path to user config directory inside the container.
  --workspace=<path> Path to project root inside the container.
  -h --help          Show this screen.
  --version          Show version.
`;

const args = docopt(doc, ARGV, true, '0.1.0');
const config = loadConfig(args['--config'], args['--workspace']);
config.workspaceDir = args['--workspace'];

run(config);
