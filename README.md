# ucode-analyzer

[![CI](https://github.com/m00qek/ucode-analyzer/actions/workflows/ci.yml/badge.svg)](https://github.com/m00qek/ucode-analyzer/actions/workflows/ci.yml)

A language server and linter for [ucode](https://github.com/jow-/ucode), the
scripting language of OpenWrt, written in ucode itself.

One engine, two front ends:

- `ucode-analyzer server` speaks the Language Server Protocol to your editor.
- `ucode-analyzer lint` checks files or a whole workspace from the command line.

Both understand plain scripts (`.uc`) and templates (`{% %}`, `{{ }}`,
`{# #}`), parse them with [tree-sitter-ucode](https://github.com/m00qek/tree-sitter-ucode),
and ship typed declarations for ucode's builtins and modules (`fs`, `uci`,
`ubus`, `uloop`, …).

Status: pre-1.0 (0.1.0), checked against real OpenWrt code (firewall4, LuCI).
Until 1.0, configuration keys and diagnostic codes may still change.

## Install

ucode-analyzer runs in a container image, an OpenWrt rootfs with its packages
installed, through a small script that makes it look like a local command.
You need Docker or Podman:

```sh
curl -fsSLo ~/.local/bin/ucode-analyzer \
  https://raw.githubusercontent.com/m00qek/ucode-analyzer/v0.1.0/bin/ucode-analyzer
chmod +x ~/.local/bin/ucode-analyzer
ucode-analyzer --version     # pulls ghcr.io/m00qek/ucode-analyzer:0.1.0 once
```

The script mounts the workspace and the current directory at their own paths,
so the locations the server reports are valid on your machine; files outside
them are not visible to it. It runs as you, without network access.
`UCODE_ANALYZER_IMAGE` picks another image, and `UCODE_ANALYZER_RUNTIME`
docker or podman.

## Features

- **Diagnostics:** syntax errors, undefined, unused and redeclared names,
  unknown imports and exports, calls to non-functions, possibly-null access, unknown
  properties, `const` reassignment, unreachable code, missing returns,
  duplicate keys, `printf` format mismatches, JSDoc inconsistencies and
  unknown type names, `type()` names it never returns (`'integer'`,
  `'null'`), arithmetic that is always NaN, deprecated APIs, `==` where `===`
  is meant. Any of them can be silenced on a line (see below).
- **Types:** flow-sensitive inference with narrowing (`if (!x) return;`,
  `x && x.y`, `type(x) == 'array'`, `if (w.timer) w.timer.cancel()`), unions, nullable values and JSDoc
  annotations (`@param`, `@returns`, `@typedef`, `@property`, `@template`).
- **Navigation:** hover with docs, go to definition, references, rename,
  document and workspace symbols, call hierarchy, document links for imports.
- **Editing:** completion, signature help, inlay hints, folding and selection
  ranges, linked editing of `{% if %}…{% endif %}` pairs, document highlight.
- **Code actions:** add a missing import, remove an unused import or a
  duplicate key, change `const` to `let`, use `===`, use optional chaining,
  generate a JSDoc block, disable a diagnostic for a line.
- **Workspace:** a cross-file dependency graph, pull diagnostics for the whole
  workspace on parallel worker processes, cancellation, and change tracking for
  open and on-disk files.

## Building

To build the packages or the image yourself: everything builds and runs in Docker, against the OpenWrt SDK and rootfs, so
the host only needs Docker and `make`:

```sh
git clone --recursive https://github.com/m00qek/ucode-analyzer
cd ucode-analyzer
make package   # OpenWrt packages, in build/x86-64/25.12/packages/
make image     # the image the script runs, as ucode-analyzer:0.1.0-amd64
make image SDK_ARCH=armsr-armv8   # the arm64 one (Apple Silicon), built without emulation
```

The packages are:

| Package | Contents |
|---|---|
| `ucode-analyzer` | the `ucode-analyzer` command: language server and linter |
| `ucode-analyzer-core` | the analysis engine and the builtin declarations |
| `ucode-mod-tree-sitter` | the tree-sitter binding and the ucode grammars |
| `ucode-analyzer-test-client` | test-only; not needed at runtime |

`ucode-analyzer` needs `ucode-docopt`, which comes from the
[packages.ucode.dev](https://m00qek.github.io/packages.ucode.dev/) feed rather
than OpenWrt's. The server runs on your machine, inside an OpenWrt rootfs
container, not on the router.

## Usage

```sh
ucode-analyzer server --config <dir> --workspace <dir>   # LSP over stdio
ucode-analyzer lint src/foo.uc src/bar.uc                 # lint some files
ucode-analyzer lint --workspace .                         # lint a workspace
ucode-analyzer lint --init                                # write .lsp/config.json
```

`ucode-analyzer lint --help` lists the options: `--format json`,
`--fail-on <severity>`, `--jobs <n>`.

In CI, `ucode-analyzer lint --workspace . --fail-on warning` fails the job
on any warning.

### Neovim

```lua
vim.lsp.config("ucode_analyzer", {
  cmd = { "ucode-analyzer", "server" },
  filetypes = { "ucode", "ucode_markup" },
  -- The nearest project config, else the repository: a folder of .uc files
  -- is not a workspace root.
  root_markers = { ".lsp", ".git" },
})
vim.lsp.enable("ucode_analyzer")
```

The `ucode` and `ucode_markup` file types, and highlighting, come from the
tree-sitter-ucode 0.9 grammars, for example through
[tree-sitter-manager.nvim](https://github.com/romus204/tree-sitter-manager.nvim)
([#215](https://github.com/romus204/tree-sitter-manager.nvim/pull/215) adds 0.9).

### Helix

With the `ucode` language set up as
[tree-sitter-ucode's guide](https://m00qek.github.io/tree-sitter-ucode/how-to/register-helix/)
describes, add to `languages.toml`:

```toml
[language-server.ucode-analyzer]
command = "ucode-analyzer"
args = ["server"]

[[language]]
name = "ucode"
language-servers = ["ucode-analyzer"]

[[language]]
name = "ucode-markup"
language-servers = ["ucode-analyzer"]
```

## Configuration

Settings come from `<workspace>/.lsp/config.json` (the project) merged over
`<config>/config.json` (the user); the project wins. All keys are optional:

```json
{
  "workspace": {
    "libraryPaths": ["src", "files/usr/share/ucode"],
    "exclude": ["build/**"],
    "globals": { "www/**": ["uhttpd"] }
  },
  "systemLibPaths": ["/usr/share/ucode"],
  "target": "24.10"
}
```

- `workspace.libraryPaths`: where `import … from 'a.b'` resolves, relative to
  the workspace. When unset, it is detected on every start: whichever of
  `src`, `test` and `files/usr/share/ucode` hold `.uc` files, else the
  workspace root. `ucode-analyzer lint --init` writes the detected value.
- `workspace.exclude`: globs of workspace files not to index or diagnose.
  Hidden folders and `node_modules` are always skipped.
- `workspace.globals`: extra global names, as a list for every file or as
  `{ "<glob>": [names] }`. LuCI's controller and template globals are known
  already.
- `systemLibPaths`: installed ucode libraries, indexed for resolution but never
  diagnosed. Defaults to `/usr/share/ucode`.
- `target`: the OpenWrt release the code runs on (`22.03`, `23.05`, `24.10`,
  `25.12`, or `main` for ucode's tip). Code that release cannot run is then
  flagged: modules its feed does not ship, and module functions, handle
  methods and builtins added after it. Unset, nothing is checked. The release
  data comes from [noah-lsp](https://github.com/NoahBPeterson/ucode-lsp).
- `debug.checkIncremental`: after an edit, check the types the server kept
  from the previous text against ones worked out from scratch, and log to
  stderr where they differ (the fresh ones are then used). It makes each edit
  a few times slower; turn it on to report a wrong type that goes away once
  you stop typing for a second, when the server works them all out afresh.

Every `.uc` file in the workspace is indexed, minus the excludes. A
subfolder with its own `.lsp/config.json` is treated as a separate workspace.

A comment silences diagnostics on one line: `// ucode-analyzer
disable-next-line` before it, or `// ucode-analyzer disable` at its end
(`/* */`, and `{# #}` in templates, work too). Codes after the keyword limit
it to those, and text after ` -- ` is a reason:

```ucode
// ucode-analyzer disable-next-line may-be-null -- the config always has it
let port = cfg.get('main', 'port').value;
```

Hover text comes from ucode templates; put your own in
`<config>/templates/hover/` to override the bundled ones
(`src/ucode_analyzer/language_server/templates/hover/`).

## Development

```sh
make test      # unit, integration and end-to-end suites (utest, in Docker)
make lint      # lint this repository with itself; fails on any warning
make compile   # rebuild the native tree-sitter module
make shell     # a shell in the test image
```

Never run the ucode sources on the host: they need the native modules of the
OpenWrt image. The layout:

- `src/ucode-analyzer.uc`: the command; `src/ucode_analyzer/cli/` holds its
  two subcommands.
- `src/ucode_analyzer/code_analysis/`: the engine (dependency graph, scope
  walk, type inference, diagnostics).
- `src/ucode_analyzer/language_server/`: the LSP protocol, handlers and code
  actions.
- `src/ucode_analyzer/linter/`: the linter front end.
- `src/ucode_analyzer/declarations/`: typed stubs for builtins and modules.
- `src/tree_sitter.uc` and `mod/tree_sitter/native.c`: the tree-sitter binding.
- `test/unit`, `test/integration`, `test/e2e`: the suites, mirroring `src/`.

[docs/architecture.md](docs/architecture.md) explains how it works, and
[docs/decisions.md](docs/decisions.md) what was decided against, and why.

## License

[MIT](LICENSE).
