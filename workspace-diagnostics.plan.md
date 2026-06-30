# Workspace diagnostics & CLI linter

## Part 1 — Workspace diagnostics (implemented)

Diagnostics use the LSP 3.17 **pull model**. There is no `publishDiagnostics`
push; clients ask for diagnostics and the server answers. This is driven by the
uloop event loop (see `uloop-integration.plan.md` for the I/O backbone).

Capability advertised in `initialize`:

```
diagnosticProvider: { interFileDependencies: true, workspaceDiagnostics: true }
```

### Per-document — `textDocument/diagnostic`

Synchronous. One file is cheap, so it is computed inline:

- `handlers/diagnostic_reports.uc::documentDiagnostics(uri, doc, prevResultId)`
  returns `{ kind: 'unchanged', resultId }` when the client's previous resultId
  still matches, else `{ kind: 'full', resultId, items }`.

### Whole project — `workspace/diagnostic`

Runs in the background so the server stays responsive on the Pi Zero floor:

- `workspaceDiagnostics(reqId, params, config)` forks a `uloop.task`. The child
  inherits the parent's state at fork time, iterates every workspace URI, and
  streams one report per file over the pipe. The parent assembles the reports
  and responds to `reqId` when the task finishes (uloop's `null` sentinel).
- Closed files are materialised on demand by `documents.getOrLoad(uri)`
  (read + parse from disk; ephemeral, not cached). We do **not** store trees in
  the DAG — re-parsing in the background child is cheaper than the memory cost.

### resultId / invalidation

- Per-URI generation counter in `diagnostic_reports.uc`; `invalidate(uri)` bumps
  it. `resultId(uri)` is just the current generation as a string.
- `lsp.uc` bumps the URI and its dependency cascade on `didOpen`, `didChange`,
  and `didChangeWatchedFiles`, so a re-pull returns `full` instead of a stale
  `unchanged`.
- `workspace/diagnostic/refresh` is sent on cross-file cascades and on-disk
  changes to prompt the client to re-pull. `didChange` keeps its document-state
  work synchronous so hover/completion always see fresh state.

### Workspace scope — `isWorkspaceUri(uri, config)`

A URI is "workspace" when its path is under `workspaceDir` and **not** under
`selfSrcDir` (the server's own bundled sources), not under any system library
root, and not a `.d.uc` declaration stub.

---

## Part 2 — CLI linter (implemented)

### Goal

Run the exact same analysis headlessly so it can gate merges in CI (and be run
locally), without an editor or the LSP handshake. One shot: load the workspace,
diagnose every workspace file, print results, exit with a status code.

### A separate entrypoint, not a subcommand

The linter is a distinct tool from the language server: a one-shot CLI with exit
codes, not a long-lived JSON-RPC/uloop process. So it gets its own entrypoint
and its own binary rather than a `lint` mode bolted onto the server.

```
src/ucode-linter.uc        # entrypoint: docopt + loadConfig, calls linter.run
src/linter/run.uc          # orchestrate: loadWorkspace -> collect -> format -> exit
src/linter/reporters.uc    # text / json (later sarif) output
```

`src/linter/**` stays **thin** — argument parsing, output formatting, exit-code
logic, orchestration. All actual analysis stays shared in `language_server/**`
(see "Shared engine" below) so the linter can never drift from what the editor
reports. Dependency direction is one-way: `linter -> language_server`, never the
reverse.

Because it skips the read loop entirely, the linter never imports `io.uc`,
`protocol.uc`, `uloop`, or `language_server.native`; it only pulls in the
analysis stack (`dag`, `documents` -> `tree_sitter.native`, `types`,
diagnostics). The `ucode-linter` binary therefore does **not** depend on
`language_server_native.so`.

### Invocation

```
Usage:
  ucode-linter [options] <file>...            # lint specific files
  ucode-linter [options] --workspace=<path>   # lint a whole workspace
  ucode-linter -h | --help
  ucode-linter --version

Options:
  --workspace=<path>    Lint every .uc file under <path>.
  --config=<path>       Config directory (defaults to the workspace; the
                        current directory in file mode).
  --format=<fmt>        Output format: text | json   [default: text]
  --fail-on=<severity>  Minimum severity that fails the run:
                        error | warning | info | hint | none   [default: error]
```

Two modes. In **file mode** (`ucode-linter a.uc b.uc`) the current directory is
the workspace root, so imports in the listed files resolve against the whole
project DAG while only the listed files are diagnosed — this is what the
`nvim-lint` on-save integration drives (per-file, exit code ignored). In
**workspace mode** (`--workspace`) every workspace file is diagnosed — this is
the CI-gating entry point.

### Flow (`src/ucode-linter.uc` -> `linter/run.uc`)

1. `loadConfig` + set `workspaceDir` (mirrors `ucode-language-server.uc`).
2. **Load the workspace** via the shared `loadWorkspace(config)`.
3. **Collect diagnostics** via the shared `collectWorkspaceDiagnostics(config)`,
   producing `[{ uri, diags }]`.
4. **Format & print** to stdout (`linter/reporters.uc`).
5. **Exit code** — 1 if any diagnostic at or above the `--fail-on` severity
   (1=Error, 2=Warning, 3=Info, 4=Hint), else 0; 2 for usage/IO errors.

### Shared engine (extract into `language_server/`, used by both)

The whole point is that the linter runs the *same* checks as the editor, so the
shared pieces are extracted once and imported by both entrypoints:

- `language_server/workspace.uc` (imports only the analysis stack — no
  protocol/io/uloop) holds:
  - `loadWorkspace(config)` — the body lifted out of the `initialized` handler
    (`dag.init`, glob+`addFromDisk` over library paths / declarations / system
    libs, `initBuiltinsFromDag`); returns the `@version` map so the caller does
    its own `platform.init`/`initAsync`. Called by both `lsp.uc`'s `initialized`
    and `linter/run.uc`.
  - `workspaceUris(config)` / `diagnoseFile(uri)` (and `isWorkspaceUri`).
  - `collectWorkspaceDiagnostics(config)` — `[{ uri, diags }]` over every
    workspace file; the linter calls it directly and synchronously.
- `handlers/diagnostic_reports.uc`'s `uloop.task` child reuses
  `workspaceUris` + `diagnoseFile` from `workspace.uc`, so the editor's
  background scan and the linter share the exact same per-file analysis.

### Output formats

- **text** (default, human/CI log friendly):
  `path:LINE:COL: [severity] message (code)` with **1-based** line/col (converted
  from LSP 0-based) and paths relative to `workspaceDir`. The bracketed lowercase
  severity is what the `nvim-lint` parser consumes. The human tally
  (`N error(s), …`) is written to **stderr**, keeping stdout pure diagnostics.
- **json** (machine-readable): `[{ uri, diagnostics: [<LSP Diagnostic>] }]` for
  downstream tooling.
- *(future)* **sarif**: for GitHub code scanning / other CI annotators.

### Why synchronous is fine here

There is no interactive client to keep responsive, so the linter skips the
`uloop.task` fork and scans in the main process. Even at the 500-file target a
one-shot scan is a few seconds — acceptable for a non-interactive command. If it
ever needs to be faster, shard the file list across N `uloop.task` workers; the
`collectWorkspaceDiagnostics` split above already isolates the unit of work.

### Testing

- Unit (`test/unit/linter/reporters_test.uc`): the pure reporters — text/json
  formatting, the human summary, and the `exitCode` threshold logic.
- e2e (`test/e2e/language_server/linter_test.uc`): run the real `ucode-linter`
  binary against `test/fixtures/linter` in both file and workspace mode; assert
  the bracket text format with 1-based positions, JSON output, and the
  `--fail-on` thresholds / exit codes (0 / 1 / 2).

### Packaging

The new entrypoint ships alongside the server in the OpenWrt package
(`openwrt/ucode-language-server/Makefile`):

- install `src/ucode-linter.uc` to `/usr/share/ucode/` and `src/linter/*` to
  `/usr/share/ucode/linter/`;
- add a `/usr/bin/ucode-linter` symlink (mirroring the existing
  `/usr/bin/ucode-language-server`).

No new native module is needed — the linter reuses `tree_sitter.native` via the
shared analysis stack. CI invokes `ucode-linter` inside the OpenWrt rootfs
container, with the workspace mounted at the same path as on the host so printed
paths resolve.
