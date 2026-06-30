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

## Part 2 — CLI linter (planned)

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
  ucode-linter --workspace=<path> [--config=<path>]
               [--format=<fmt>] [--fail-on=<severity>]
  ucode-linter -h | --help
  ucode-linter --version

Options:
  --format=<fmt>        Output format: text | json   [default: text]
  --fail-on=<severity>  Minimum severity that fails the run:
                        error | warning | info | hint | none   [default: error]
```

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

- `language_server/workspace.uc::loadWorkspace(config)` — the body currently
  inside the `initialized` handler (`dag.init`, glob+`addFromDisk` over library
  paths / declarations / system libs, `initBuiltinsFromDag`, `platform.init`).
  Called by both `lsp.uc`'s `initialized` and `linter/run.uc`.
- `handlers/diagnostic_reports.uc::collectWorkspaceDiagnostics(config)` — the
  per-file scan loop (every `isWorkspaceUri` -> `getOrLoad` + `diagnosticsFor`),
  extracted out of the `uloop.task` child. The task child becomes a thin wrapper
  that streams the results of this function; the linter calls it directly and
  synchronously (no fork needed for a one-shot run).

### Output formats

- **text** (default, human/CI log friendly):
  `path:LINE:COL: SEVERITY: message (code)` with **1-based** line/col (converted
  from LSP 0-based), paths relative to `workspaceDir`. Trailing summary, e.g.
  `3 errors, 5 warnings across 42 files`.
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

- Integration test: run `ucode-linter` against a fixture directory with known
  errors/warnings; assert stdout (both formats) and the exit code, including
  `--fail-on` thresholds.

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
