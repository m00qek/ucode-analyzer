## LSP Implementation Plan

---

### Repo structure

```
ucode-language-server/
  bindings/
    ucode/
      ts_binding.c       ← tree-sitter C extension
      CMakeLists.txt
  src/
    protocol/
      rpc.uc             ← JSON-RPC framing
      documents.uc       ← document sync
      dispatcher.uc      ← method routing
      positions.uc       ← LSP ↔ byte offset translation
    dag/
      node.uc            ← module node representation
      edge.uc            ← exported symbol + type
      dag.uc             ← DAG operations
      indexer.uc         ← background file indexer
    types/
      parser.uc          ← ucdocs type expression parser
      unifier.uc         ← @template substitution
      registry.uc        ← @typedef cross-file registry
    inference/
      inferrer.uc        ← pattern-based type inference
      scope.uc           ← lambda scope tracker
      memo.uc            ← memoization + dirty bits
    features/
      hover.uc
      definition.uc
      completion.uc
      diagnostics.uc
    templates/
      hover.uc           ← default markup hover template
    lsp.uc               ← main entry point
  test/
    e2e/
      harness.uc         ← LspClient wrapper
      initialize_test.uc
      hover_test.uc
      definition_test.uc
      completion_test.uc
      diagnostics_test.uc
    unit/
      rpc_test.uc
      positions_test.uc
      dag_test.uc
      type_parser_test.uc
      unifier_test.uc
      inferrer_test.uc
  stubs/
    fs.d.uc
    uloop.d.uc
    ubus.d.uc
    uci.d.uc
    math.d.uc
    socket.d.uc
  package.json           ← npm wrapper script
  bin/
    launch.js            ← host wrapper, docker exec bridge
  ucode-lsp.json.example ← project config template
  CMakeLists.txt
```

---

### Milestone 0 — Tree-sitter C extension (`bindings/ucode/ts_binding.c`)

This is the load-bearing piece everything else depends on. Write and validate it before any LSP code.

**What to expose to ucode:**

```c
// Parser lifecycle
ts_new_parser(language)     → parser handle
ts_parse(parser, source)    → tree handle
ts_reparse(parser, tree, source, edits) → tree handle

// Tree walking
ts_root_node(tree)          → node
ts_node_type(node)          → string
ts_node_is_named(node)      → bool
ts_node_text(node, source)  → string
ts_node_start(node)         → { row, column, byte }
ts_node_end(node)           → { row, column, byte }
ts_node_child_count(node)   → int
ts_node_child(node, n)      → node
ts_node_named_child(node, n) → node
ts_node_named_child_count(node) → int
ts_node_child_by_field(node, field) → node
ts_node_parent(node)        → node

// Query API
ts_query_new(language, pattern) → query handle
ts_query_matches(query, node, source) → [{ pattern, captures: { name → node } }]
ts_query_captures(query, node, source) → [{ name, node }]

// Language handles
ts_language_ucode()         → language handle
ts_language_ucdocs()        → language handle
```

**Memory ownership rules to get right in C:**

- `TSTree` — owned, must be freed. Old tree must stay alive until `ts_reparse` returns.
- `TSNode` — value type (stack struct), only valid while parent tree is alive. Ucode node objects must hold a reference to their parent tree to prevent premature GC.
- `TSQuery` — long-lived, compile once per pattern string and cache.
- `TSParser` — one per language, long-lived.

**The node→tree reference pattern:**

```c
typedef struct {
    uc_value_t *tree_ref;   // holds tree alive via ucode GC ref
    TSNode node;
} uc_ts_node_t;
```

Every node object returned to ucode carries this struct. When the ucode GC frees the node object, the destructor releases the tree ref.

**Validation test before moving on:**

```js
import { ts_new_parser, ts_parse, ts_root_node,
         ts_node_type, ts_node_text, ts_language_ucode } from 'ts';

let parser = ts_new_parser(ts_language_ucode());
let tree = ts_parse(parser, 'let x = 5;');
let root = ts_root_node(tree);
assert.equal(ts_node_type(root), 'program');
```

If this passes, the extension is viable.

---

### Milestone 1 — Test infrastructure

Build this before any real LSP logic so every subsequent feature has an executable definition of done.

**1a. `spawn_with_pipes` C extension**

Minimal POSIX implementation:

```c
// fork + exec with stdin/stdout pipes
// returns { write(data), read(n), close() }
static uc_value_t *uc_spawn(uc_vm_t *vm, size_t nargs)
{
    int stdin_pipe[2], stdout_pipe[2];
    pipe(stdin_pipe);
    pipe(stdout_pipe);

    pid_t pid = fork();
    if (pid == 0) {
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        // close all other fds
        execvp(path, argv);
        _exit(1);
    }
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);
    // return handle with write fd and read fd
}
```

Key subtleties: close unused pipe ends immediately after fork, handle `SIGCHLD` or use `waitpid` with `WNOHANG` in `close()`, set `O_CLOEXEC` on all fds to avoid leaking into grandchildren.

**1b. LSP test harness (`test/e2e/harness.uc`)**

```js
import { spawn } from 'spawn_pipes';

export function LspClient(args) {
    let proc = spawn('ucode', args);
    let nextId = 1;
    let pending = {};      // id → resolve fn
    let notifications = [];

    function send(msg) {
        let json = JSON.stringify(msg);
        proc.write(`Content-Length: ${length(json)}\r\n\r\n${json}`);
    }

    function recv() {
        // read Content-Length header
        let header = '';
        while (!match(header, /Content-Length: (\d+)/)) {
            header += proc.read(1);
        }
        let len = int(match(header, /Content-Length: (\d+)/)[1]);
        // skip \r\n\r\n
        proc.read(4);
        return JSON.parse(proc.read(len));
    }

    function recvUntil(id) {
        while (true) {
            let msg = recv();
            if (msg.id == id) return msg.result;
            if (!msg.id) push(notifications, msg); // notification
        }
    }

    return {
        initialize: (rootUri) => {
            let id = nextId++;
            send({ jsonrpc: "2.0", id, method: "initialize",
                   params: { rootUri, capabilities: {} } });
            let result = recvUntil(id);
            send({ jsonrpc: "2.0", method: "initialized", params: {} });
            return result;
        },
        openDocument: (uri, text) => {
            send({ jsonrpc: "2.0", method: "textDocument/didOpen",
                   params: { textDocument: { uri, languageId: "ucode",
                                             version: 1, text } } });
        },
        hover: (uri, line, character) => {
            let id = nextId++;
            send({ jsonrpc: "2.0", id, method: "textDocument/hover",
                   params: { textDocument: { uri },
                             position: { line, character } } });
            return recvUntil(id);
        },
        definition: (uri, line, character) => {
            let id = nextId++;
            send({ jsonrpc: "2.0", id, method: "textDocument/definition",
                   params: { textDocument: { uri },
                             position: { line, character } } });
            return recvUntil(id);
        },
        completion: (uri, line, character) => {
            let id = nextId++;
            send({ jsonrpc: "2.0", id,
                   method: "textDocument/completion",
                   params: { textDocument: { uri },
                             position: { line, character } } });
            return recvUntil(id);
        },
        notifications: () => notifications,
        stop: () => proc.close()
    };
}
```

**1c. Skeleton e2e test to validate the harness itself:**

```js
import { LspClient } from 'harness';
import { describe, it } from 'utest';

describe("LSP skeleton", () => {
    it("responds to initialize", () => {
        let lsp = LspClient(['src/lsp.uc']);
        let caps = lsp.initialize('file:///tmp/test');
        assert.type(caps.capabilities, "object");
        lsp.stop();
    });
});
```

This test should pass before writing any real language intelligence. The LSP's `initialize` handler can return a hardcoded capabilities object.

---

### Milestone 2 — LSP protocol layer

**2a. JSON-RPC framing (`src/protocol/rpc.uc`)**

```js
export function readMessage() {
    let header = io.stdin.readline();
    while (header != '\r\n') {
        if (match(header, /^Content-Length: (\d+)/)) {
            let len = int(match(header, /Content-Length: (\d+)/)[1]);
            io.stdin.readline(); // consume \r\n
            return JSON.parse(io.stdin.read(len));
        }
        header = io.stdin.readline();
    }
}

export function writeMessage(msg) {
    let json = JSON.stringify(msg);
    io.stdout.write(
        `Content-Length: ${length(json)}\r\n\r\n${json}`
    );
    io.stdout.flush();
}

export function respond(id, result) {
    writeMessage({ jsonrpc: "2.0", id, result });
}

export function respondError(id, code, message) {
    writeMessage({ jsonrpc: "2.0", id,
                   error: { code, message } });
}

export function notify(method, params) {
    writeMessage({ jsonrpc: "2.0", method, params });
}
```

**2b. Position/offset translation (`src/protocol/positions.uc`)**

This is where UTF-16 bites you if you don't get it right upfront. LSP uses UTF-16 code unit offsets, Tree-sitter uses byte offsets.

```js
// Build line start byte-offset table from document text
export function buildLineTable(text) {
    let lines = [0];  // line 0 starts at byte 0
    for (let i = 0; i < length(text); i++) {
        if (text[i] == '\n')
            push(lines, i + 1);
    }
    return lines;
}

// LSP position → byte offset
// Must handle UTF-16: each BMP char = 1 unit, non-BMP = 2 units
export function positionToOffset(text, lineTable, position) {
    let lineStart = lineTable[position.line];
    let col = position.character;  // UTF-16 units
    let i = lineStart;
    let utf16 = 0;
    while (utf16 < col && i < length(text)) {
        let cp = codepoint(text, i);  // need byte-aware codepoint fn
        utf16 += cp > 0xFFFF ? 2 : 1;
        i += utf8_char_len(cp);
    }
    return i;
}

// Byte offset → LSP position
export function offsetToPosition(text, lineTable, offset) {
    // binary search lineTable for the line
    let line = upperBound(lineTable, offset) - 1;
    let lineStart = lineTable[line];
    // count UTF-16 units from lineStart to offset
    let character = 0;
    for (let i = lineStart; i < offset;) {
        let cp = codepoint(text, i);
        character += cp > 0xFFFF ? 2 : 1;
        i += utf8_char_len(cp);
    }
    return { line, character };
}
```

Property tests for this module from utest are high value — generate random strings with random line endings and verify round-trip correctness.

**2c. Document sync (`src/protocol/documents.uc`)**

Start with full sync — editor sends complete text on every change:

```js
let documents = {};  // uri → { text, version, tree, lineTable }

export function open(uri, text, version) {
    let lineTable = buildLineTable(text);
    let tree = ts_parse(ucodeParser, text);
    documents[uri] = { text, version, tree, lineTable };
}

export function change(uri, changes, version) {
    // full sync: changes[0].text is the complete new content
    let text = changes[0].text;
    documents[uri] = {
        text,
        version,
        lineTable: buildLineTable(text),
        tree: ts_parse(ucodeParser, text)
    };
}

export function get(uri) { return documents[uri]; }
export function close(uri) { delete documents[uri]; }
```

Incremental sync (applying `TextDocumentContentChangeEvent` deltas and calling `ts_reparse`) is a v2 optimization. Full sync is correct and simpler.

**2d. Dispatcher (`src/protocol/dispatcher.uc`)**

```js
let handlers = {};

export function register(method, fn) {
    handlers[method] = fn;
}

export function dispatch(msg) {
    let handler = handlers[msg.method];
    if (!handler) {
        if (msg.id)
            respondError(msg.id, -32601, `Method not found: ${msg.method}`);
        return;
    }
    try {
        let result = handler(msg.params);
        if (msg.id) respond(msg.id, result);
    } catch(e) {
        if (msg.id) respondError(msg.id, -32603, `${e}`);
    }
}
```

**2e. Main loop (`src/lsp.uc`)**

```js
import { readMessage, respond } from 'protocol/rpc';
import { dispatch, register } from 'protocol/dispatcher';
import { open, change, close } from 'protocol/documents';

// register built-in handlers
register('initialize', (params) => {
    // store rootUri for workspace resolution
    return {
        capabilities: {
            textDocumentSync: 1,  // full sync
            hoverProvider: true,
            definitionProvider: true,
            completionProvider: { triggerCharacters: ['.'] }
        }
    };
});

register('initialized', () => null);
register('shutdown', () => null);
register('exit', () => exit(0));

register('textDocument/didOpen', (params) => {
    let td = params.textDocument;
    open(td.uri, td.text, td.version);
    return null;
});

register('textDocument/didChange', (params) => {
    change(params.textDocument.uri,
           params.contentChanges,
           params.textDocument.version);
    return null;
});

register('textDocument/didClose', (params) => {
    close(params.textDocument.uri);
    return null;
});

// main event loop
while (true) {
    let msg = readMessage();
    if (msg) dispatch(msg);
}
```

At this point the skeleton LSP is runnable. Point an editor at it and `initialize` + `didOpen` work. The e2e test from milestone 1 passes.

---

### Milestone 3 — DAG and indexer

**3a. Edge and node representation (`src/dag/`)**

```js
// node.uc
export function makeNode(uri) {
    return {
        uri,
        exports: {},     // name → { type, jsdoc, definedAt }
        imports: [],     // [{ fromUri, symbols: [name] }]
        moduleDoc: null  // parsed module-level /** */
    };
}

// edge.uc
export function makeEdge(sourceUri, targetUri, symbolName, type, jsdoc, originalUri) {
    return { sourceUri, targetUri, symbolName, type, jsdoc, originalUri };
}
```

**3b. DAG operations (`src/dag/dag.uc`)**

```js
let nodes = {};   // uri → node
let edges = [];   // flat array of edge objects
let reverseIndex = {}; // uri → [edges where targetUri == uri]

export function addNode(uri) {
    nodes[uri] = makeNode(uri);
}

export function addEdge(edge) {
    push(edges, edge);
    reverseIndex[edge.targetUri] ??= [];
    push(reverseIndex[edge.targetUri], edge);
}

export function getNode(uri) { return nodes[uri]; }

export function getEdgesFrom(uri) {
    return filter(edges, e => e.sourceUri == uri);
}

export function getEdgesTo(uri) {
    return reverseIndex[uri] ?? [];
}

// Reverse-edge traversal for invalidation
export function dependents(uri) {
    return map(getEdgesTo(uri), e => e.sourceUri);
}

// Cycle detection — DFS
export function findCycles() {
    let cycles = [];
    let visited = {};
    let stack = {};

    function dfs(uri) {
        visited[uri] = true;
        stack[uri] = true;
        for (let dep in dependents(uri)) {
            if (!visited[dep]) dfs(dep);
            else if (stack[dep])
                push(cycles, dep);
        }
        delete stack[uri];
    }

    for (let uri in keys(nodes))
        if (!visited[uri]) dfs(uri);

    return cycles;
}
```

**3c. Indexer (`src/dag/indexer.uc`)**

The indexer runs on startup and on file save. For each file it:

1. Parses the file with the ucode grammar
2. Finds all `export` declarations
3. Parses the attached `/** */` block with the ucdocs grammar
4. Extracts symbol name, type, and jsdoc
5. Finds all `import` statements and builds edges

```js
import { ts_new_parser, ts_parse, ts_query_captures,
         ts_node_text, ts_language_ucode,
         ts_language_ucdocs } from 'ts';

// Pre-compiled queries — compile once, reuse forever
let ucodeParser = ts_new_parser(ts_language_ucode());
let ucdocsParser = ts_new_parser(ts_language_ucdocs());

// Query: find all export declarations with preceding comment
let exportQuery = ts_query_new(ts_language_ucode(), `
    (comment) @doc
    .
    (export_statement
      (function_declaration
        name: (identifier) @name)) @export

    (comment) @doc
    .
    (export_statement
      declaration: (lexical_declaration
        (variable_declarator
          name: (identifier) @name))) @export
`);

// Query: find all import statements
let importQuery = ts_query_new(ts_language_ucode(), `
    (import_statement
      (import_clause
        (named_imports
          (import_specifier
            name: (identifier) @name)))
      source: (string) @source)
`);

// Query: parse ucdocs for a single comment block
let paramQuery = ts_query_new(ts_language_ucdocs(), `
    (param_tag
      type: (type_expression) @type
      name: (identifier) @name)
    (returns_tag
      type: (type_expression) @type)
    (template_tag
      (type_param) @param)
`);

export function indexFile(uri, text) {
    let tree = ts_parse(ucodeParser, text);
    let node = getNode(uri) ?? addNode(uri);

    // extract exports
    for (let cap in ts_query_captures(exportQuery, ts_root_node(tree), text)) {
        if (cap.name == 'name') {
            let symbolName = ts_node_text(cap.node, text);
            let jsdoc = extractPrecedingDoc(cap.node, text);
            let type = jsdoc ? parseJsdocType(jsdoc, text) : null;
            node.exports[symbolName] = { type, jsdoc,
                                          definedAt: ts_node_start(cap.node) };
        }
    }

    // extract imports and build edges
    for (let cap in ts_query_captures(importQuery, ts_root_node(tree), text)) {
        // group by source, then create edges
        // ... resolve relative path to absolute URI
        // ... create edge for each imported symbol
    }

    // check for module doc (first comment before any statement)
    node.moduleDoc = extractModuleDoc(tree, text);
}
```

**3d. Re-export collapsing**

Run after all files are indexed:

```js
export function collapseReexports() {
    // for each edge where the symbol is re-exported from targetUri
    // walk the chain until we find the original definition
    // stamp the resolved type and originalUri onto the edge
    for (let edge in edges) {
        if (isReexport(edge)) {
            let { type, originalUri } = resolveReexport(edge);
            edge.type = type;
            edge.originalUri = originalUri;
        }
    }
}
```

Run cycle detection before this pass — a cycle in re-exports would cause infinite recursion here.

**3e. Invalidation**

On file save, dirty-mark the changed file and all dependents:

```js
export function invalidate(uri) {
    let dirty = new Set([uri]);
    for (let dep in dependents(uri))
        dirty.add(dep);
    for (let u in dirty)
        reindexFile(u);
}
```

At 400 nodes this is fast enough to run synchronously.

---

### Milestone 4 — Type system

**4a. Type parser (`src/types/parser.uc`)**

Recursive descent over the ucdocs type expression AST — at this point you have structured nodes, not strings, so this is just a tree walk:

```js
export function parseTypeNode(node, source) {
    switch (ts_node_type(node)) {
        case 'primitive_type':
            return { kind: 'primitive',
                     name: ts_node_text(node, source) };

        case 'generic_type':
            return {
                kind: 'generic',
                base: ts_node_text(
                    ts_node_child_by_field(node, 'base'), source),
                params: map(
                    namedChildren(ts_node_child_by_field(node, 'params')),
                    p => parseTypeNode(p, source))
            };

        case 'union_type':
            return {
                kind: 'union',
                members: flattenUnion(node, source)
            };

        case 'function_type':
            return {
                kind: 'function',
                params: parseParams(
                    ts_node_child_by_field(node, 'params'), source),
                return: parseTypeNode(
                    ts_node_child_by_field(node, 'return'), source)
            };

        case 'nullable_type':
            return {
                kind: 'union',
                members: [
                    parseTypeNode(ts_node_named_child(node, 0), source),
                    { kind: 'primitive', name: 'null' }
                ]
            };

        case 'type_identifier':
        case 'type_param':
            return { kind: 'ref',
                     name: ts_node_text(node, source) };

        case 'any_type':
            return { kind: 'unknown' };

        default:
            return { kind: 'unknown' };
    }
}
```

**4b. Type registry (`src/types/registry.uc`)**

Stores `@typedef` definitions from all indexed files:

```js
let registry = {};  // name → { type, sourceUri }

export function registerTypedef(name, type, sourceUri) {
    registry[name] = { type, sourceUri };
}

export function resolve(name) {
    return registry[name] ?? null;
}

// Expand a type ref recursively (with depth guard)
export function expand(type, depth = 0) {
    if (depth > 5) return { kind: 'unknown' };
    if (type.kind != 'ref') return type;
    let def = resolve(type.name);
    if (!def) return type;  // unresolved ref stays as ref
    return expand(def.type, depth + 1);
}
```

**4c. Unifier (`src/types/unifier.uc`)**

Matches a parameterized type against a concrete type to produce bindings:

```js
export function unify(paramType, argType, bindings, depth = 0) {
    if (depth > 5) return;

    if (paramType.kind == 'ref' && isTypeParam(paramType.name)) {
        // T = concrete
        bindings[paramType.name] = argType;
        return;
    }

    if (paramType.kind == 'generic' && argType.kind == 'generic'
        && paramType.base == argType.base) {
        for (let i = 0; i < length(paramType.params); i++)
            unify(paramType.params[i], argType.params[i],
                  bindings, depth + 1);
        return;
    }

    if (paramType.kind == 'function' && argType.kind == 'function') {
        for (let i = 0; i < length(paramType.params); i++)
            unify(paramType.params[i].type, argType.params[i].type,
                  bindings, depth + 1);
        unify(paramType.return, argType.return, bindings, depth + 1);
    }
}

// Apply bindings to a type
export function substitute(type, bindings) {
    if (type.kind == 'ref' && bindings[type.name])
        return bindings[type.name];
    if (type.kind == 'generic')
        return { ...type,
                 params: map(type.params, p => substitute(p, bindings)) };
    if (type.kind == 'function')
        return { ...type,
                 params: map(type.params, p =>
                    ({ ...p, type: substitute(p.type, bindings) })),
                 return: substitute(type.return, bindings) };
    return type;
}

function isTypeParam(name) {
    return match(name, /^[A-Z]$/);
}
```

---

### Milestone 5 — Inference engine

**5a. Memo layer (`src/inference/memo.uc`)**

```js
// keyed by node's start byte offset within a URI
// cleared per-URI on file change
let cache = {};  // uri → { offset → type }

export function memoGet(uri, offset) {
    return cache[uri]?.[offset] ?? null;
}

export function memoSet(uri, offset, type) {
    cache[uri] ??= {};
    cache[uri][offset] = type;
}

export function invalidateUri(uri) {
    delete cache[uri];
}
```

**5b. Scope tracker (`src/inference/scope.uc`)**

```js
export function makeScope(parent = null) {
    return { bindings: {}, parent };
}

export function scopeSet(scope, name, type) {
    scope.bindings[name] = type;
}

export function scopeGet(scope, name) {
    if (scope.bindings[name]) return scope.bindings[name];
    if (scope.parent) return scopeGet(scope.parent, name);
    return null;
}
```

**5c. Inferrer (`src/inference/inferrer.uc`)**

```js
import { memoGet, memoSet } from 'memo';
import { scopeGet, makeScope, scopeSet } from 'scope';
import { unify, substitute } from 'types/unifier';

export function inferNode(node, source, uri, scope, depth = 0) {
    if (depth > 5) return { kind: 'unknown' };

    let offset = ts_node_start(node).byte;
    let cached = memoGet(uri, offset);
    if (cached) return cached;

    let type = inferNodeInner(node, source, uri, scope, depth);
    memoSet(uri, offset, type);
    return type;
}

function inferNodeInner(node, source, uri, scope, depth) {
    switch (ts_node_type(node)) {

        case 'number':
            let text = ts_node_text(node, source);
            return { kind: 'primitive',
                     name: match(text, /\./) ? 'float' : 'int' };

        case 'string':
            return { kind: 'primitive', name: 'string' };

        case 'true': case 'false':
            return { kind: 'primitive', name: 'boolean' };

        case 'null':
            return { kind: 'primitive', name: 'null' };

        case 'identifier': {
            let name = ts_node_text(node, source);
            return scopeGet(scope, name) ?? lookupExport(uri, name)
                   ?? { kind: 'unknown' };
        }

        case 'binary_expression': {
            let op = ts_node_child(node, 1);
            let opText = ts_node_text(op, source);
            if (match(opText, /[+\-*\/%]/))
                return { kind: 'primitive', name: 'int' }; // simplified
            if (match(opText, /[<>=!]|&&|\|\|/))
                return { kind: 'primitive', name: 'boolean' };
            return { kind: 'unknown' };
        }

        case 'call_expression': {
            let fn = ts_node_child_by_field(node, 'function');
            let fnType = inferNode(fn, source, uri, scope, depth + 1);
            if (fnType.kind != 'function') return { kind: 'unknown' };

            let args = namedChildren(
                ts_node_child_by_field(node, 'arguments'));
            let bindings = {};
            for (let i = 0; i < length(args); i++) {
                let argType = inferNode(args[i], source, uri,
                                        scope, depth + 1);
                unify(fnType.params[i]?.type ?? { kind: 'unknown' },
                      argType, bindings);
            }
            return substitute(fnType.return, bindings);
        }

        case 'arrow_function': {
            // don't infer body — return function type with unknown return
            // unless we have a pushed-down expected type
            let params = extractArrowParams(node, source);
            return {
                kind: 'function',
                params,
                return: { kind: 'unknown' }
            };
        }

        case 'object': {
            // { key: value, ... } → dict<T> if homogeneous
            return { kind: 'unknown' }; // simplified for v1
        }

        case 'array':
            return { kind: 'generic', base: 'list',
                     params: [{ kind: 'unknown' }] };

        default:
            return { kind: 'unknown' };
    }
}
```

---

### Milestone 6 — LSP features

**6a. Hover (`src/features/hover.uc`)**

```js
import { get } from 'protocol/documents';
import { positionToOffset, offsetToPosition } from 'protocol/positions';
import { inferNode } from 'inference/inferrer';
import { render } from 'templates/hover';

export function hover(params) {
    let uri = params.textDocument.uri;
    let doc = get(uri);
    if (!doc) return null;

    let offset = positionToOffset(doc.text, doc.lineTable,
                                   params.position);
    let node = nodeAtOffset(doc.tree, offset);
    if (!node) return null;

    // try DAG lookup first (imported symbol)
    let dagResult = dagHover(uri, node, doc.text);
    if (dagResult) return { contents: { kind: 'markdown',
                                         value: render(dagResult) } };

    // fall back to local inference
    let type = inferNode(node, doc.text, uri, globalScope(uri));
    if (type.kind == 'unknown') return null;

    return {
        contents: { kind: 'markdown',
                    value: render({ type, symbol: ts_node_text(node, doc.text) }) },
        range: nodeRange(node, doc)
    };
}

function nodeAtOffset(tree, offset) {
    // walk from root, descend into the smallest named node containing offset
    let node = ts_root_node(tree);
    while (true) {
        let child = namedChildContaining(node, offset);
        if (!child) return node;
        node = child;
    }
}
```

**6b. Go to definition (`src/features/definition.uc`)**

```js
export function definition(params) {
    let uri = params.textDocument.uri;
    let doc = get(uri);
    let offset = positionToOffset(doc.text, doc.lineTable,
                                   params.position);
    let node = nodeAtOffset(doc.tree, offset);
    let name = ts_node_text(node, doc.text);

    // check if it's an imported identifier
    let edge = findEdge(uri, name);
    if (edge) {
        let targetDoc = get(edge.originalUri);
        if (!targetDoc) return null;
        let pos = offsetToPosition(targetDoc.text,
                                    targetDoc.lineTable,
                                    edge.jsdoc.definedAt.byte);
        return { uri: edge.originalUri, range: { start: pos, end: pos } };
    }

    // local definition search
    let defNode = findLocalDefinition(doc.tree, name, doc.text);
    if (!defNode) return null;
    let pos = offsetToPosition(doc.text, doc.lineTable,
                                ts_node_start(defNode).byte);
    return { uri, range: { start: pos, end: pos } };
}
```

**6c. Completions (`src/features/completion.uc`)**

```js
export function completion(params) {
    let uri = params.textDocument.uri;
    let doc = get(uri);
    let offset = positionToOffset(doc.text, doc.lineTable,
                                   params.position);

    // are we inside an import statement?
    let importCtx = importContext(doc.tree, offset, doc.text);
    if (importCtx) {
        // offer all exports from the target module
        let targetUri = resolveUri(uri, importCtx.source);
        let targetNode = getNode(targetUri);
        if (!targetNode) return [];
        return map(keys(targetNode.exports), name => ({
            label: name,
            kind: 3,  // Function
            detail: formatType(targetNode.exports[name].type),
            documentation: targetNode.exports[name].jsdoc?.description
        }));
    }

    // general scope completion
    let items = [];
    // local scope
    for (let name in localScope(doc.tree, offset, doc.text))
        push(items, { label: name, kind: 6 }); // Variable

    // imported symbols
    for (let edge in getEdgesFrom(uri))
        push(items, {
            label: edge.symbolName,
            kind: 3,
            detail: formatType(edge.type)
        });

    return items;
}
```

**6d. Diagnostics (`src/features/diagnostics.uc`)**

```js
export function computeDiagnostics(uri) {
    let diagnostics = [];

    // cycle detection
    let cycles = findCycles();
    for (let cycleUri in cycles) {
        if (cycleUri == uri)
            push(diagnostics, {
                range: { start: { line: 0, character: 0 },
                         end: { line: 0, character: 0 } },
                severity: 1,  // Error
                message: `Circular dependency detected`
            });
    }

    // unknown imports
    let doc = get(uri);
    for (let edge in getEdgesFrom(uri)) {
        if (!getNode(edge.targetUri))
            push(diagnostics, {
                range: nodeRange(edge.importNode, doc),
                severity: 1,
                message: `Cannot find module '${edge.targetUri}'`
            });
        else if (!getNode(edge.targetUri).exports[edge.symbolName])
            push(diagnostics, {
                range: nodeRange(edge.importNode, doc),
                severity: 1,
                message: `Module has no export '${edge.symbolName}'`
            });
    }

    notify('textDocument/publishDiagnostics', { uri, diagnostics });
}
```

---

### Milestone 7 — Hover template

Default template at `src/templates/hover.uc`:

```
{%- if symbol.signature %}
```ucode
{{ symbol.signature }}
```
{%- endif %}

{{ symbol.description }}

{%- if symbol.params %}
**Parameters**
{%- for p in symbol.params %}
- `{{ p.name }}` `{{ p.type }}` — {{ p.description }}
{%- endfor %}
{%- endif %}

{%- if symbol.returns %}
**Returns** `{{ symbol.returns.type }}`{%- if symbol.returns.description %} — {{ symbol.returns.description }}{%- endif %}
{%- endif %}

{%- if symbol.throws %}
**Throws** `{{ symbol.throws.type }}` — {{ symbol.throws.description }}
{%- endif %}

{%- if symbol.example %}
**Example**
```ucode
{{ symbol.example }}
```
{%- endif %}

{%- if symbol.deprecated %}
> ⚠️ **Deprecated** {{ symbol.deprecated }}
{%- endif %}

{%- if symbol.since %}
*Since {{ symbol.since }}*
{%- endif %}
```

User override path: `~/.config/ucode-lsp/hover.uc`. LSP checks that path at startup, falls back to bundled template.

---

### Milestone 8 — npm wrapper (`bin/launch.js`)

```js
#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// read config
const configPath = path.join(process.cwd(), 'ucode-lsp.json');
const config = fs.existsSync(configPath)
    ? JSON.parse(fs.readFileSync(configPath, 'utf8'))
    : {};

const containerName = config.docker?.containerName
    ?? `ucode-lsp-${hash(process.cwd())}`;
const containerPath = config.docker?.containerPath ?? '/workspace';
const image = config.docker?.image ?? 'openwrt/sdk:latest';

// check if container is running
try {
    execSync(`docker inspect -f '{{.State.Running}}' ${containerName}`,
             { stdio: 'pipe' });
} catch {
    // start it
    execSync([
        `docker run -d`,
        `--name ${containerName}`,
        `--memory=512m --cpus=1.0`,
        `-v "${process.cwd()}:${containerPath}"`,
        image,
        `sleep infinity`
    ].join(' '));
}

// bridge editor stdio → container
const proc = spawn('docker',
    ['exec', '-i', containerName, 'ucode', '/usr/lib/ucode-lsp/lsp.uc'],
    { stdio: 'inherit' });

proc.on('exit', code => process.exit(code ?? 0));
```

`stdio: 'inherit'` makes the wrapper fully transparent — it doesn't parse or buffer LSP messages, just passes file descriptors through.

---

### Sequencing and time estimates

| Milestone | What | Est. |
|---|---|---|
| 0 | Tree-sitter C extension | 3 days |
| 1 | `spawn_with_pipes` + test harness | 2 days |
| 2 | Protocol layer (RPC, positions, sync, dispatcher) | 3 days |
| 3 | DAG + indexer | 4 days |
| 4 | Type system (parser, registry, unifier) | 3 days |
| 5 | Inference engine | 3 days |
| 6 | LSP features (hover, definition, completion, diagnostics) | 4 days |
| 7 | Hover template | 1 day |
| 8 | npm wrapper + Docker bridge | 1 day |

**~24 working days** to a functional v1 LSP. The C extension and DAG indexer are the critical path — nothing else is testable until those exist. The inference engine (milestone 5) can be developed incrementally since every feature degrades gracefully to `unknown` without it.
