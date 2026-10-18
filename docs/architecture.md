# Architecture

How ucode-analyzer is put together, for contributors. [decisions.md](decisions.md)
records what was decided against, and why. Paths are relative to
`src/ucode_analyzer/code_analysis/` unless stated.

## ucode is not JavaScript

ucode looks like JavaScript, and assuming it is has caused real bugs. Check a
construct against the interpreter (`make shell`, then `ucode -e '…'`), not
against intuition or the grammar:

- **The grammar is a superset of the language.** tree-sitter-ucode parses some
  constructs ucode rejects, so "it parses" does not make a snippet valid ucode.
  Before calling a diagnostic a false positive, run its trigger.
- **No destructuring**, except in import clauses (`import { a, b } from '…'`).
- **No default or named parameters.**
- **No hoisting.** A declaration binds its name when its statement runs, so
  calling a function above its declaration fails. In the analyzer's own code,
  a function referenced before its definition resolves as a global: define
  helpers before their users, or declare them with `let` first.
- **A closure sees a loop variable's last value.** `for (let x in xs)` shares
  one `x` across iterations; copy it into a `let` inside the body (one `it()`
  per case in a loop needs this).
- Object shorthand `{ foo }` is supported; duplicate keys are legal (the last
  wins), which makes flagging them a valid lint.

## Constraints

- **Where it runs:** on the developer's machine or CI, in a Docker container of
  the OpenWrt rootfs, so every OpenWrt ucode module is available. Workspaces
  are mounted at their host path, so the `file://` URIs it returns are valid on
  the host.
- **The floor:** a Raspberry Pi Zero 2 (four 1 GHz ARM cores) must be usable,
  if slow. Design for **2 cores**: interactive features must not depend on
  more, batch work may scale to the cores present, and correctness never
  depends on the count. Hold memory to **512 MB** as a discipline (real hosts
  have more) and remember the container takes part of it.
- **Scale:** up to 500 modules per workspace. Interactive work should not grow
  with the workspace; what does (indexing at startup, cross-file references)
  runs in workers, off the event loop.
- **Precision over recall:** when the analyzer is unsure, it says nothing. An
  unknown type is `{ kind: 'unknown' }`, and checks treat it as fine.

## The engine

- **Documents (`documents.uc`):** open documents as `{ uri, text, version,
  tree, lineTable, scopeMap }`. The scope map is built on first `get()`,
  because it resolves imports: an edit, or `markStale()` when an import
  changes, only drops it.
- **Template or script (`mode.uc`):** both use `.uc`, so the mode comes from
  the shebang, else from a template tag opener in code position. A template is
  one statement stream, so it carries the same node types as a script.
- **Dependency graph (`dag/`):** every file the server knows, open or on disk:
  exports (with doc, parameter names and literal types), imports and their
  resolved targets, module docs and versions. An edit re-indexes the file and
  cascades to its importers only when its interface (exports without
  positions) changed.
- **Scope map (`types/scope_walk.uc`):** one top-down walk per document emits
  sorted `(offset, scope)` checkpoints; every feature asks
  `scopeAtOffset(doc.scopeMap, offset)` instead of propagating scopes itself.
  Scopes are copy-on-write (`scopeFork`). The walk narrows on guards (`if (!x)
  return;`, `x && x.y`, branches), widens a variable assigned in a branch, a
  loop or another function, and follows `=`, `??=` and `||=`.
- **Type inference (`types/inferrer.uc`):** `inferNode(node, source, uri,
  scope, depth)`, memoized per node and scope in `memo.uc`. A function's
  return type is inferred on first read: read it only through `returnOf()`.
  Types imported from other files come from their doc comments and the
  indexer's records (`types/dag_bridge.uc`), never from inference, so a
  type never outlives its document.
- **Types:** plain objects with a `kind`: `primitive` (`int`, `float`,
  `string`, `boolean`, `null`), `function`, `record`, `generic` (`list`,
  `dict`), `module`, `nullable` (this or null), `union`, `ref` (a `@typedef`
  name) and `unknown`. `types/narrowing.uc` applies guards;
  `types/unifier.uc` resolves type parameters for callbacks.
- **Declarations (`../declarations/*.d.uc`):** typed stubs for the builtins
  (`global.d.uc`) and every ucode module, with `// Versions:` headers that
  `platform.uc` checks against the installed packages.

## Diagnostics

`diagnostics.uc` runs one pass per file in `diagnostics/`, each isolated: a
pass that throws contributes nothing and logs, and the others still report. A
pass and its file are named after the code it reports (`unused_var`,
`unused-var`); those reporting several codes (`type_errors`, `format_string`)
after what they check. Passes that only need certain node types find them with
`ts.descendants()` in C rather than walking the tree in ucode.

`workspace/diagnostic` runs in the background: `parallel.uc` forks
`detectJobs()` workers over shards of the workspace and answers when they
finish. A newer request kills the scan and answers the older one with
ContentModified. A worker resets SIGTERM and reports ready before it may be
killed: killed earlier, it could relay the signal to the server's own handler.
`textDocument/diagnostic` for one file runs in-process below 16 KB and in a
worker above (a plan, see below), so a large file's passes do not hold up the
hover or completion that follows an edit; a change to the file or its imports
answers a pull still running with ContentModified. An unchanged file answers
`unchanged` by resultId.

Startup indexing runs the same way (`workspace.loadWorkspaceAsync`): one
worker lists the files, others build each file's index record, and the DAG
installs them all when the last arrives, in the synchronous order, so typedef precedence does not depend on
timing. Meanwhile the server answers from what it has, except for requests a
partial index would answer wrongly (diagnostics, references, rename, incoming
calls, workspace symbols): those are held until the load ends. A file indexed
in-process during the load (opened, changed on disk) keeps that newer index.
A client that supports work-done progress sees the load as `$/progress`
(`language_server/progress.uc`).

References, rename and incoming calls grow with an export's importers. Their
handlers return a plan, `{ items, work, finish }`, one item per importing file
(`language_server/background.uc`): up to 16 files it runs in-process, more in
workers, answering when they finish or when the request is cancelled.

Worker results travel in pieces of at most PIPE_BUF bytes: uloop drops a
message larger than the pipe's buffer when its reader catches up with the
writer.

## Tests

`make test` runs everything in Docker; never run the sources on the host.

- Mark positions in snippets with `$0`…`$9` instead of counting columns:
  `cursors(text)` and `locate(fileText, needle)` in `test/helpers/cursor.uc`.
- Import and navigation fixtures live in `test/fixtures/workspace/`
  (`test/helpers/fixture.uc`), with `parser.uc` as the library to import.
  Never use the analyzer's own sources as fixtures.
- End-to-end tests start a real server with `lsp.connect()`
  (`test/helpers/client.uc`), on the fixture workspace by default; a test that
  needs other contents builds a temporary workspace.
- To run one end-to-end file by hand, also mount
  `build/x86-64/25.12/rpc_client_native.so` at
  `/usr/lib/ucode/rpc_client/native.so`, as the Makefile does.
- `make lint` lints the repository with itself and must stay clean.

## Out of scope

- **Formatting**, which would need a full ucode pretty-printer.
- **Running on the router:** this is a developer tool.
