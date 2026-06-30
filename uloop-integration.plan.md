# uloop integration plan

## Why

The current server is a blocking `while(true)` loop. Every handler runs to completion
before the next message is read. On a Pi Zero 2, expensive operations (diagnosing a
file on `didChange`, scanning 500 files for workspace diagnostics) make the server
visibly unresponsive — hover and completion queue behind them.

uloop gives us three things:
- `handle()` — fd-based stdin watching, replaces the blocking read loop
- `timer()` — deferred/debounced execution
- `task()` — fork a child process with a serialisation pipe (actual parallelism)

## What changes

### Phase 1 — Non-blocking stdin (prerequisite for everything)

**`protocol.uc`**: replace blocking `read_header` / `read_exact` with a buffer
that accumulates data as it arrives. Export `startListening(dispatch)` instead of
`read_message()`:

```
let _buf = '';

export function startListening(dispatch) {
    uloop.handle(fs.stdin, function() {
        let chunk = fs.stdin.read(4096);
        if (length(chunk) === 0) { exit(shutdown_requested ? 0 : 1); return; }
        _buf += chunk;

        while (true) {
            let headerEnd = index(_buf, '\r\n\r\n');
            if (headerEnd < 0) break;

            let header = substr(_buf, 0, headerEnd);
            let m = match(header, /Content-Length: ([0-9]+)/);
            if (!m) die('missing Content-Length');

            let bodyLen = +m[1];
            let msgStart = headerEnd + 4;
            if (length(_buf) < msgStart + bodyLen) break;

            let body = substr(_buf, msgStart, bodyLen);
            _buf = substr(_buf, msgStart + bodyLen);
            dispatch(body);
        }
    }, uloop.ULOOP_READ);
};
```

**`lsp.uc`**: replace the `while(true)` loop with:

```javascript
export function run(config) {
    uloop.init();
    // … handler setup unchanged …

    protocol.startListening(function(body) {
        let msg;
        try { msg = json(body); }
        catch (e) { /* respond ParseError */ return; }
        // … same dispatch logic as today …
    });

    uloop.signal('SIGTERM', () => uloop.end());
    uloop.run();
};
```

Everything else in `lsp.uc` is unchanged — handlers are still plain functions called
synchronously from the dispatch callback. The difference is that the event loop
returns to watching stdin between messages, so timers and task callbacks can fire
between them.

---

### Phase 2 — Debounce `didChange` diagnostics

The most user-visible win. Currently every keystroke triggers `diagnosticsFor`.

Split `didChange` into two parts:

1. **Immediate** (must stay synchronous — hover/completion depend on fresh state):
   - `documents.change` (re-parse)
   - `invalidateUri`
   - `dag.update` + cascade invalidations
   - `documents.refreshScopeMap`

2. **Deferred** via a 300 ms timer:
   - `diagnosticsFor` + `publishDiagnostics`

```javascript
let _diagTimer = null;

'textDocument/didChange': function(msg) {
    // immediate: keep doc state fresh
    let uri = msg.params.textDocument.uri;
    documents.change(uri, msg.params.contentChanges, msg.params.textDocument.version);
    let doc = documents.get(uri);
    if (!doc) return;
    invalidateUri(uri);
    let cascaded = dag.update(uri, doc.text, doc.tree, documents.all());
    for (let dep in cascaded) invalidateUri(dep);
    documents.refreshScopeMap(uri);

    // deferred: diagnose after typing pauses
    if (_diagTimer) _diagTimer.set(300);
    else _diagTimer = uloop.timer(300, function() {
        _diagTimer = null;
        let doc = documents.get(uri);
        if (!doc) return;
        protocol.notify('textDocument/publishDiagnostics', {
            uri, version: doc.version,
            diagnostics: diagnosticsFor(uri, doc),
        });
    });
},
```

`didOpen` is not debounced — the file is freshly opened so diagnosing immediately
is correct and expected.

---

### Phase 3 — Background workspace scan with `uloop.task`

`uloop.task()` forks a child process. The child runs a function, sends results back
via `pipe.send(value)` (JSON-serialised), and the parent receives them via an output
callback — without blocking the main event loop.

This replaces the batched-refresh approach in `workspace-diagnostics.plan.md`.
The child processes all files synchronously (blocking is fine in the child); the
parent stays fully responsive throughout.

**`diagnostic_cache.uc`** — simplified vs the earlier plan. No `_pending` queue,
no `nextBatch`, no `pendingCount`. Just resultId tracking:

```
let _gen   = {}   // uri → int
let _cache = {}   // uri → { resultId, diags }

invalidate(uri)   → _gen[uri]++, delete _cache[uri]
currentId(uri)    → string(_gen[uri] ?? 0)
get(uri)          → _cache[uri] ?? null
set(uri, diags)   → _cache[uri] = { resultId: currentId(uri), diags }
```

**`handlers/workspace_diagnostics.uc`**:

```javascript
let _activeTask   = null;  // currently running uloop.task handle
let _pendingReqId = null;  // request ID waiting for task to finish
let _results      = [];    // accumulated items from child

export function workspaceDiagnostics(requestId, params, workspaceDir) {
    // Cancel any in-progress scan (stale — a new request arrived)
    if (_activeTask) { _activeTask.kill(); _activeTask = null; }

    let prevIds = {};
    for (let r in (params.previousResultIds ?? []))
        prevIds[r.uri] = r.value;

    _pendingReqId = requestId;
    _results = [];

    _activeTask = uloop.task(
        // ── child process ──────────────────────────────────────────
        function(pipe) {
            let uris = filter(dag.allUris(), (u) => isUnderWorkspace(u, workspaceDir));
            for (let uri in uris) {
                let cached = diagnostic_cache.get(uri);
                if (cached && cached.resultId === (prevIds[uri] ?? null)) {
                    pipe.send({ kind: 'unchanged', uri, resultId: cached.resultId });
                } else {
                    let doc   = documents.getOrLoad(uri);
                    let diags = doc ? diagnosticsFor(uri, doc) : [];
                    pipe.send({ kind: 'full', uri, diags });
                }
            }
        },
        // ── parent: output callback (fires for each pipe.send) ─────
        function(item) {
            if (item.kind === 'unchanged') {
                push(_results, { kind: 'unchanged', uri: item.uri, resultId: item.resultId });
            } else {
                diagnostic_cache.set(item.uri, item.diags);
                push(_results, {
                    kind:     'full',
                    uri:      item.uri,
                    resultId: diagnostic_cache.currentId(item.uri),
                    items:    item.diags,
                    version:  null,
                });
            }
            // If task finished (null sentinel or task.finished()), respond
            if (_activeTask && _activeTask.finished()) {
                protocol.respond(_pendingReqId, { kind: 'full', items: _results });
                _activeTask   = null;
                _pendingReqId = null;
                _results      = [];
            }
        }
    );

    // Task is now running in background — do NOT respond to the request yet.
};
```

**`lsp.uc`** additions:

```javascript
// capability
diagnosticProvider: { interFileDependencies: true, workspaceDiagnostics: true }

// handler
'workspace/diagnostic': function(msg) {
    workspaceDiagnostics(msg.id, msg.params, config.workspaceDir);
},

// invalidate on file changes
'workspace/didChangeWatchedFiles': function(msg) {
    for (let change in (msg.params.changes ?? [])) {
        // … existing invalidateUri logic …
        diagnostic_cache.invalidate(uri);
        for (let dep in revDeps) diagnostic_cache.invalidate(dep);
    }
    protocol.notify('workspace/diagnostic/refresh', {});
},

// keep push and pull caches in sync
'textDocument/didOpen' / 'textDocument/didChange' (after deferred diag fires):
    diagnostic_cache.set(uri, diags);
```

---

## What `uloop.task` changes vs the earlier workspace diagnostics plan

| Earlier plan | This plan |
|---|---|
| Batched (10 files/request) + `workspace/diagnostic/refresh` loop | Child processes all files; parent responds once when done |
| `_pending` queue, `nextBatch`, `pendingCount` in `diagnostic_cache` | Removed — task handles sequencing |
| Multiple round-trips for 500 files | One request → one response (async) |
| Message loop blocked during each batch | Message loop free throughout; child runs in parallel |
| `getOrLoad` re-parses each file | Still true (child gets a copy of DAG state at fork time) |

The child process inherits the full ucode state at fork time (DAG, documents, all
imports already resolved). It does not need `dag.addFromDisk` — the data is already
there. The tradeoff: if the user edits a file while the child is running, the child
diagnoses stale content. That is acceptable — workspace diagnostics are eventually
consistent by design, and the next `workspace/diagnostic/refresh` cycle picks up
the changes.

## Phase ordering

1. **Phase 1** (stdin) is a prerequisite for phases 2 and 3.
2. **Phase 2** (debounce) is independent of phase 3 and delivers immediate value
   for interactive use on constrained hardware.
3. **Phase 3** (task) depends on phase 1 and supersedes the
   `workspace-diagnostics.plan.md` batching approach.

Implement in order: 1 → 2 → 3.
