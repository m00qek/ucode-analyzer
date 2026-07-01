## Remaining work

> Completed work lives in git history and `CLAUDE.md`; decisions we deliberately
> did not act on live in `decisions.md`. This file tracks open items only.

---

### To do

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
