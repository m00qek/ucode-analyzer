## Remaining work

---

### Done

**uloop I/O backbone**
- Non-blocking stdin: `protocol.startListening(dispatch, onEof)` over `uloop.handle(fs.stdin, …, ULOOP_READ)`; `lsp.uc` runs `uloop.init()` / `uloop.signal('SIGTERM')` / `uloop.run()` instead of a blocking `while(true)`. Timers and `uloop.task` callbacks fire between messages.

**`workspace/diagnostic` (pull model)**
- Pull-based workspace-wide diagnostics (LSP 3.17): `handlers/diagnostic_reports.uc` computes per-document reports inline and forks a background `uloop.task` for the whole-project scan, so the server stays responsive on the Pi Zero floor. Per-URI resultId generation + `invalidate` cascade; `workspace/diagnostic/refresh` on cross-file / on-disk changes. `didChange` keeps document-state work synchronous and never pushes — clients re-pull. (This replaced the earlier push + 300 ms debounce idea, which is now moot: there is no push path left to debounce.)

**CLI linter**
- `ucode-linter` runs the exact same analysis headlessly (file and workspace modes) for CI gating and on-save `nvim-lint`. Entry `src/ucode-linter.uc` → `src/linter/run.uc` + `src/linter/reporters.uc` (text/json), over the shared `code_analysis.workspace` engine (`loadWorkspace` / `collectWorkspaceDiagnostics`). No native module of its own — reuses `tree_sitter.native`.

---

### To do

**Discriminated-union narrowing** — see `discriminated-unions.plan.md`
- `unionOf` collapses record variants, so a function returning tagged records infers to one variant and `if (r.kind === 'fail') r.value` is misdiagnosed.
- Phased: fix `unionOf` (clears the false positives on its own), then literal types + discriminant guards for real narrowing. Full design in the dedicated plan.

**Assignment widening**
- `let x = 1; if (cond) x = "hello";` — after the if block, `x` should be `int | string`.
- Requires tracking assignments across branches and widening to a union at join points. Architectural change to scope_builder / inferrer.

---

### Deferred

**`completionItem/resolve`**
- Lazy-load documentation when the user dwells on a completion item.
- Currently all docs are computed eagerly at completion time, so this adds little. Only matters if completion starts getting slow for very large modules.

**`textDocument/linkedEditingRange`**
- Rename matching block pairs (`if`/`endif`, `for`/`endfor`, `while`/`endwhile`, `function`/`endfunction`) together.
- Only relevant in template mode (`.uwrt` files). Moderate effort: walk the tree to find the matching close-keyword for the open-keyword under the cursor.

**`textDocument/semanticTokens/full`**
- Semantic highlighting on top of TextMate grammar: distinguish local variables, imported names, function declarations by token type and modifiers.
- Large effort. Editors fall back gracefully to syntax-only highlighting.

**`textDocument/formatting`**
- Full ucode pretty-printer from scratch. Not realistic given the device constraints and the absence of an existing formatter to wrap.
