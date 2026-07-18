# tree-sitter-ucode upgrade plan (v0.7.0 → post-0.7.0 line)

Status as of 2026-07-18. The `third_party/tree-sitter-ucode` submodule working tree
is checked out at tag **`v0.8.0`** (`e77c851`), **not committed**. v0.8.0 is the
`de9bf7e` tree I validated + a pure version bump (`minor_version 7→8`, version
strings) — no grammar/scanner/query/node-type change, so the analysis below holds
byte-for-byte. The two upstream bugs found during the first review (ASI swallowing
own-line comments; ucdocs `{T}` losing to brace-text) are fixed and corpus-pinned
upstream (`7d498d3` / `f6ae41c`) — verified here by tree-level probes and the suite.

Suite at `de9bf7e`/`v0.8.0`: unit **1075 pass / 9 fail**, integration **216/216**,
e2e **182/182**, `make lint` zero. All 9 remaining failures are the deliberate
markup-grammar restructure, i.e. migration work on our side — no known upstream
defects remain.

## What changed upstream that affects us

1. **Template spanning forms got new node types.** The markup grammar's
   tag-spanning colon forms (`{% if (x): %} … {% endif %}` etc.) moved from
   `if/for/for_in/while_alt_statement` to new `*_alt_statement_tag` types.
   The old `*_alt_statement` names still exist — they are now only the
   *inline* colon forms (fully inside one statement tag / script colon syntax).
   Both shapes carry the same fields (`condition`, `left`, `right`,
   `initializer`, `increment`, `body`, …).
2. **Clause tags now contain their bodies.** `elif_clause_tag` /
   `else_alt_clause_tag` were empty markers with sibling bodies (flat);
   they now nest their body statements (like the inline `elif_clause` /
   `else_alt_clause` forms that `walkIfAlt` already handles).
3. **New brace-spanning statement forms parse structurally** instead of
   erroring: `if/for/for_in/while/try_statement_tag`,
   `function_declaration_tag`, `function_alt_declaration`,
   `catch/else/elseif_clause_tag` (e.g. `{% if (x) { %}text{% } %}`).
   Today these fall through to `walkNode`'s generic recursion: identifiers are
   still visited but no scope checkpoints are emitted inside them.
4. **Script grammar no longer parses markup tags** — no impact; mode detection
   in `mode.uc` is content-based and templates always use the markup parser.
5. **Strictness now matches the interpreter** (verified with `ucode -e`):
   numeric object keys, `\400` escapes, empty import lists, bare `try` are all
   real syntax errors; `**` is left-associative (`2**3**2 == 64`). Good for the
   precision-over-recall policy; no code change needed.
6. New `_asi_gap` zero-width scanner token is a *hidden* extra — it never
   appears as a node, so no consumer can see it.

## Migration tasks (ordered)

Tasks 1–3 **DONE** on 2026-07-18 (`.uc`-only, no C change). Full suite after:
unit **1084/0**, integration **216/0**, e2e **182/0**, `make lint` zero — the
9 restructure failures cleared, no regressions.

### 1. `scope_walk.uc` — dispatch the `*_alt_statement_tag` renames — DONE
`walkNode` now branches on `for_in_alt_statement || for_in_alt_statement_tag`
and likewise for `for` / `while` / `if` (old inline names KEPT — still live for
colon forms). Verified the `_tag` nodes are structurally identical to the
v0.7.0 forms the walkers were written against (same fields/header fields), so
`walkForInAlt`/`walkForAlt`/`walkWhileAlt`/`walkIfAlt` needed no body changes.
Also updated **`definition.uc`** (loop-var go-to-def, lines 129/141) with the
same rename — plan originally under-scoped this to `scope_walk.uc`, but the
`for_in`/`for` def-resolution is the identical spanning-form rename and would
otherwise silently break go-to-def for a `{% for %}` loop variable.

### 2. `walkIfAlt` — treat clause tags as body-containing — DONE
The `elif_clause_tag` / `else_alt_clause_tag` marker arms were deleted; the
tag names now route through the existing inline-clause arm (`ct === 'elif_clause'
|| 'elif_clause_tag' || 'else_alt_clause' || 'else_alt_clause_tag'`). Confirmed
the tag clauses expose the same `condition` (parenthesized_expression) + body
shape that arm already consumes via `walkAltBody`, so it was drop-in reuse.
Inline colon-form handling preserved (its test still passes).

### 3. `mode_test.uc` — update the pinned node name — DONE
`mode_test.uc:124` now pins `for_in_alt_statement_tag`. `topLevelStatements`
needed no change. (Deferred nicety: also pin a brace-spanning `if_statement_tag`
as pass-through — folded into task 4's test work.)

### 4. The new brace-spanning forms — DONE (Option A, full support)
`for_in/for/while/if/try_statement_tag`, `function_declaration_tag`,
`function_alt_declaration` (the `{% … { %}…{% } %}` brace forms, plus the colon
`function` form) previously hit `walkNode`'s default recursion — no checkpoints,
no binding threading, so scope/narrowing degraded to the enclosing scope.
Implemented across four commits:
- **loop trio** (`for_in/for/while_statement_tag`): structurally identical to the
  `*_alt_statement_tag` forms → routed to the existing walkers, no new code.
- **`if_statement_tag`**: routed to `walkIfAlt`; its clause-narrowing arm now
  also recognizes `elseif_clause_tag`/`else_clause_tag` (the brace form's
  differently-named clauses).
- **`try_statement_tag`**: new `walkTryTag` (try + `catch_clause_tag` bodies
  threaded via `walkAltBody`, catch param bound as string). `altHeaderBytes`
  extended with `handler`/`parameter`/`name`/`parameters`.
- **function forms**: new `walkFnTag` + `bindTagFnParams` (params bound UNKNOWN —
  the inferrer doesn't model these node types, so no JSDoc param typing).
- **go-to-def** (`definition.uc` `binderIn`): extended to resolve loop vars,
  catch params, and function params in all the new tag forms — the `localScopeDef`
  ancestor chain already descends into them, so only `binderIn` needed the names.
Each step shipped with `scope_walk_test`/`definition_test` coverage. Full suite
green. `undefined_vars.uc` walks generically in source order and needed no change.

### 5. Add regression tests for the two fixed upstream bugs
Cheap insurance against a grammar re-regression, since our features depend on
both behaviors:
- doc association across an ASI boundary: `function f() {…}` + `/** doc */` +
  `export const …` → `extractExports` doc present (unit, `indexer_test`).
- `parseDoc("/** @template T @param {T} x */")` → `params[0].type` resolves
  (already covered by `doc_parser_test`, which now passes — keep it).

### 6. Commit strategy for the submodule bump
- Upstream has now tagged **`v0.8.0`** (the node-type renames are breaking, so
  the minor bump is warranted). Commit the submodule pin at `v0.8.0` **together
  with** the migration from tasks 1–3 in one commit so the repo never has a
  half-migrated state (old grammar + new code, or vice versa).
- Bump message should note the breaking markup node renames and that this is a
  tagged release (`v0.8.0`), aligning with the existing pin convention.
- Core tree-sitter (C lib) is a separate, optional chore: pin is v0.26.9;
  v0.26.10/11 exist on `release-0.26` (query internals/aliasing fixes only,
  no API we call). Bump opportunistically in its own commit; do not bundle.

## Verification checklist (after tasks 1–3)
- `make test` fully green (unit + integration + e2e), `make lint` zero.
- Template oracle spot-check: linter over the firewall4 corpus (sibling
  `../firewall4`) — diagnostics should match the pre-upgrade run (colon-form
  templates are the corpus's only template shape).
- Probe hover/narrowing inside a `{% elif %}` body in a scratch template to
  confirm checkpoints exist (was the silent-degradation case).
