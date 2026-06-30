# Workspace diagnostics — pull model

## Goals

Implement `workspace/diagnostic` (LSP 3.17) so clients can request diagnostics for
all project files at once, enabling Problems panels and CLI lint workflows without
opening every file.

## Constraints

- Single-threaded ucode: no async, no threads. Every `workspace/diagnostic` handler
  invocation blocks the message loop until it returns.
- Developer machine floor: usable on a 1 GHz single-core ARM (Pi Zero 2), 512 MB RAM.
- Scale target: up to 500 `.uc` modules per workspace.
- Consequence: a single blocking response over all files is unacceptable. Use batched
  processing with `workspace/diagnostic/refresh` to keep the message loop responsive.

## Design decisions

**Batched with refresh.** Process ~10 files per `workspace/diagnostic` request, then
send `workspace/diagnostic/refresh` to prompt the next batch. 500 files → ~50
round-trips. Each batch blocks for bounded time; hover/completion requests are served
between batches.

**Store tree in DAG.** `addFromDisk` already parses the tree but throws it away.
Retaining it in `_nodes` means `getOrLoad` (for non-open files) costs only
`buildScopeMap`, not a disk read + re-parse. This is the critical Pi Zero 2
optimisation — tree-sitter parsing is the expensive native call.

**Open files first.** `nextBatch` moves open URIs to the front of the pending queue.
The user sees diagnostics for what they're actively editing before the cold scan
finishes.

**Workspace-only scope.** Only diagnose files under `workspaceDir`. Declaration files
(`*.d.uc`), system libs, and the LSP server's own sources are excluded.

**Sync push and pull caches.** After `diagnosticsFor` runs for an open file (existing
`didOpen`/`didChange` push path), store the result in `diagnostic_cache` so the next
pull request sees `unchanged` for that file without re-diagnosing it.

## Steps

### Step 1 — Store text + tree in `dag/dag.uc`

Change `indexNode` to include `text` and `tree` in `_nodes[uri]`:

```javascript
_nodes[uri] = { exports, imports, moduleDoc, versions, text, tree };
```

Expose two new accessors:

```javascript
export function textOf(uri) { return _nodes[uri]?.text ?? null; }
export function treeOf(uri) { return _nodes[uri]?.tree ?? null; }
```

### Step 2 — `documents.getOrLoad(uri)` in `documents.uc`

Returns the open doc if present, otherwise synthesises an ephemeral doc from DAG
state (no disk I/O, no re-parse):

```javascript
export function getOrLoad(uri) {
    let doc = _documents[uri];
    if (doc) return doc;
    let text = dag.textOf(uri);
    let tree = dag.treeOf(uri);
    if (!text || !tree) return null;
    return {
        uri,
        text,
        tree,
        lineTable: buildLineTable(text),
        scopeMap:  buildScopeMap(uri, text, tree),
    };
};
```

The returned object is **not** stored in `_documents` — it is ephemeral.

### Step 3 — `diagnostic_cache.uc` (new file)

```
let _gen     = {}   // uri → int  (generation counter, monotonically increasing)
let _cache   = {}   // uri → { resultId: string, diags: [...] }
let _pending = []   // ordered list of URIs awaiting diagnosis/re-diagnosis
let _inPending = {} // uri → true  (O(1) membership test for _pending)

invalidateAll(uris, workspaceDir)
  — seed _pending with all workspace URIs (excludes .d.uc, system libs)
  — called once from `initialized` after the workspace scan

invalidate(uri)
  — _gen[uri]++, delete _cache[uri]
  — push to _pending if not already there

currentId(uri)  → string(_gen[uri] ?? 0)
get(uri)        → _cache[uri] ?? null
set(uri, diags) → _cache[uri] = { resultId: currentId(uri), diags }
                  remove uri from _inPending

nextBatch(n, openUris)
  — move any openUris that appear in _pending to the front
  — pop and return min(n, length(_pending)) URIs

pendingCount()  → length(_pending)
allKnown()      → keys(_gen)   (all URIs ever seen by the cache)
```

### Step 4 — `handlers/workspace_diagnostics.uc` (new file)

```javascript
import { diagnosticsFor } from 'language_server.handlers.diagnostics';
import * as documents from 'language_server.documents';
import * as diagnostic_cache from 'language_server.diagnostic_cache';

const BATCH_SIZE = 10;

export function workspaceDiagnostics(params, openUris) {
    let prevIds = {};
    for (let r in (params.previousResultIds ?? []))
        prevIds[r.uri] = r.value;

    let batch = {};
    for (let uri in diagnostic_cache.nextBatch(BATCH_SIZE, openUris))
        batch[uri] = true;

    let items = [];
    for (let uri in diagnostic_cache.allKnown()) {
        let cached = diagnostic_cache.get(uri);
        if (cached && cached.resultId === (prevIds[uri] ?? null)) {
            push(items, { kind: 'unchanged', uri, resultId: cached.resultId });
        } else if (batch[uri]) {
            let doc   = documents.getOrLoad(uri);
            let diags = doc ? diagnosticsFor(uri, doc) : [];
            diagnostic_cache.set(uri, diags);
            push(items, {
                kind:     'full',
                uri,
                resultId: diagnostic_cache.currentId(uri),
                items:    diags,
                version:  null,
            });
        }
        // else: still pending — omit from response; client gets it in a future batch
    }

    return { items, hasMore: diagnostic_cache.pendingCount() > 0 };
};
```

### Step 5 — `lsp.uc` wiring

**`initialize` response** — add capability:
```javascript
diagnosticProvider: { interFileDependencies: true, workspaceDiagnostics: true }
```

**`initialized`** — after the workspace scan loop, seed the pending queue:
```javascript
diagnostic_cache.invalidateAll(dag.allUris(), config.workspaceDir);
```

**New handler:**
```javascript
'workspace/diagnostic': function(msg) {
    let result = workspaceDiagnostics(msg.params, documents.all());
    protocol.respond(msg.id, { kind: 'full', items: result.items });
    if (result.hasMore)
        protocol.notify('workspace/diagnostic/refresh', {});
},
```

**`workspace/didChangeWatchedFiles`** — after existing `invalidateUri` calls:
```javascript
diagnostic_cache.invalidate(uri);
for (let dep in revDeps) diagnostic_cache.invalidate(dep);
// … existing logic …
protocol.notify('workspace/diagnostic/refresh', {});
```

**`textDocument/didOpen` / `didChange`** — after the existing push, sync the cache:
```javascript
diagnostic_cache.set(uri, diags);
```

## What is NOT in scope

- `textDocument/diagnostic` (per-file pull): the existing push path covers open files.
  Clients that require per-file pull can be addressed later.
- Partial results via `$/progress`: cosmetic in a single-threaded server (still blocks
  for the full batch duration). Not worth the complexity.
- Batch size auto-tuning: start at 10, adjust based on real-world feedback.
