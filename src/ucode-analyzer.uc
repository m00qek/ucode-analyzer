#!/usr/bin/ucode
'use strict';

// ucode-analyzer: the language server, or with `lint` the linter.

import { main as server } from 'ucode_analyzer.cli.server';
import { main as lint } from 'ucode_analyzer.cli.lint';

// The package directory sits next to this script, installed or not.
const pkgDir = sourcepath(0, true) + '/ucode_analyzer';

if (ARGV[0] === 'lint')
	exit(lint(ARGV, pkgDir));
server(ARGV, pkgDir);
