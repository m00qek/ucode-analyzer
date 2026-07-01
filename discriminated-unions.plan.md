# Discriminated-union narrowing plan (category C)

## Why

Functions that return several record shapes — the classic tagged-variant pattern —
infer to an imprecise type, so field access on the result is misdiagnosed:

```
function try_choices(...) {
    ...
    return { kind: 'invalid' };
    return { kind: 'pass' };
    return { kind: 'fail', value, error };
}

const r = try_choices(...);
if (r.kind === 'fail') {
    r.value    // ← today: "Property 'value' does not exist" (false positive)
}
```

Two defects stack up:

1. **`unionOf` collapses records.** `inferrer.uc` builds the return type as
   `unionOf(rets)`, but `unionOf` (`types/type_utils.uc`) only name-checks
   `primitive`/`ref` when deduplicating — every `record` is treated as identical,
   so the three variants collapse to the *first* one (`{kind:'invalid'}`). `r`
   ends up as a single variant with only a `kind` field.
2. **No discriminant narrowing.** Even with a real union, `if (r.kind === 'fail')`
   does not refine `r` to the matching variant, because guards are keyed by bare
   variable name and there are no literal types to match `'fail'` against.

The goal: infer the true union, and refine it to one variant inside a branch that
tests the discriminant — so safe access is allowed and genuinely-wrong-variant
access is flagged.

## Guiding constraints (keep the blast radius contained)

- **Literals are a *refinement* of `primitive`, never a new kind.** A literal is
  `{ kind: 'primitive', name: 'string', value: 'fail' }` — an extra `value` field.
  Every existing `type.kind === 'primitive'` / `name === 'string'` check keeps
  working untouched; literal-awareness is opt-in only where it matters (`unionOf`
  dedup, discriminant narrowing). Introducing `kind: 'literal'` instead would turn
  all ~66 `type.kind` sites into places that can silently mishandle it — do not.
- **Literals widen to their base by default.** They are *produced* only where a
  discriminant needs them (object-literal field values), and widened everywhere
  else. This leans on the analyzer's existing leniency (`unknown` = assume-OK, no
  assignability enforcement) so a leaked literal has almost no way to become a
  false positive. The one durable rule for future contributors: **treat a literal
  as its base type unless you specifically care about the value.**
- **Narrowing stays name-keyed.** A discriminant guard still rebinds the variable
  `r` in the branch scope (via the existing `applyGuard` → `scopeSet` model); only
  the *condition* parser and a union-filter helper are new. No new soundness class
  is introduced — reassignment-between-guard-and-use is already assumed unsound by
  every current guard.

---

## Phase 0 — `unionOf` preserves distinct record variants (prerequisite = C1)

Without a real union there is nothing to narrow, and this phase alone removes the
current false positives (because `unknownFieldOf` already returns `null` for union
types — silent-but-safe).

**`types/type_utils.uc`**: dedup records by their **field-name set** instead of
collapsing them:

```
// in unionOf's dedup inner loop, replace the record case:
if (t.kind === 'record' && !sameFieldNames(m, t)) continue;
```

where `sameFieldNames` compares sorted field-name lists. Two `{kind:'invalid'}`
returns still collapse; `{kind:'fail', value, error}` stays distinct.

- Ships independently. Verify the suite: unions get larger, so some hover /
  inference expectations may shift.

---

## Phase 1 — Literal types (primitive refinement)

**`types/type_utils.uc`**: helpers.

```
export function literal(name, value) { return { kind: 'primitive', name, value }; }
export function widen(type) {
    if (type.kind === 'primitive' && exists(type, 'value'))
        return { kind: 'primitive', name: type.name };
    return type;
}
```

**`types/inferrer.uc`**: infer string / number literal nodes to literal types
(`literal('string', 'fail')`, `literal('int', 42)`), **but only where the value is
load-bearing** — i.e. as the value type of an object-literal field in `inferObject`.
Everywhere a literal would otherwise flow outward (a `let` binding read back, a
call argument, a return position), widen it. Starting conservative — literals live
essentially only inside record fields — keeps propagation near-zero while still
carrying the discriminant.

**`types/unifier.uc` (`substitute`) / `type_utils.uc` (`unionOf`)**: literal-aware.
`unionOf` collapses two equal literals, and widens `literal | base` to `base`
(a value plus its own base type is just the base).

**`types/doc_parser.uc` (`typeToString`)**: render a literal as its base name (or
optionally the quoted value in hover). Do not let literals leak into user-visible
type strings as a surprise.

---

## Phase 2 — Discriminant guards in `narrowing.uc`

**`parseGuard`**: recognize `identifier.field === <string|int literal>` and the
`!==` form, emitting a new guard:

```
{ kind: 'variant', name, field, value, positive }
```

This slots in beside the existing `type(x) === 'string'` handling and composes with
`&&` via the existing `{ kind: 'and', guards }` path.

**`applyGuard`**: for a `variant` guard, refine the union bound to `name`:

```
// true branch: keep members whose `field` is a literal === value
// false branch: drop those members
scopeSet(scope, guard.name,
    narrowUnionByDiscriminant(current ?? UNKNOWN, guard.field, guard.value, inTrueBranch));
```

**`narrowUnionByDiscriminant(type, field, value, keep)`** (new helper): resolve
refs, require `type` to be a union of records; partition members by whether their
`field` type is a literal equal to `value`; return the kept sub-union (or the sole
survivor, or `UNKNOWN` if none). Non-union or non-literal-discriminant inputs are
returned unchanged — narrowing simply doesn't fire (safe fallback).

After this phase, inside `if (r.kind === 'fail')` the scope map binds `r` to the
single `fail` record, so `r.value` / `r.error` resolve and stop being flagged.

---

## Phase 3 — Make `unknown-property` opinionated on unions (optional precision)

Once a branch narrows `r` to one variant, the *existing* `unknownFieldOf` already
checks it — so `r.value` outside a `fail`-guarded branch (where `r` is still the
full union) currently stays silent. Decide the union policy in
`diagnostics/type_errors.uc::unknownFieldOf`:

- **Conservative (recommended default):** flag a field only when it is absent from
  **every** member of the union (definitely wrong regardless of variant); otherwise
  stay silent. This is the smallest, safest step up from "silent on all unions."
- **Strict:** flag whenever the field is absent from *any* reachable member. More
  true positives, but noisier on unions the analyzer can't fully narrow — defer.

This phase is what turns C2 from "permit safe access" into "also catch wrong-variant
access." It is separable; Phases 0–2 already remove the false positives.

---

## Testing

- **`unionOf`** (`type_utils_test`): distinct records preserved; identical records
  dedup; `literal | base` widens to `base`; two equal literals collapse.
- **inferrer** (`inferrer_test`): an object-literal field carries a literal type;
  the same value in a `let` read-back is widened.
- **narrowing** (`narrowing_test`): `r.kind === 'fail'` true branch yields the fail
  variant; false branch yields the complement; `&&` composition; a non-literal or
  non-union discriminant leaves the type unchanged (no narrowing, no crash).
- **type errors** (e2e fixture mirroring `property.uc`): `r.value` allowed inside
  the `fail` branch; (Phase 3) flagged in a branch where `r` cannot be `fail`.

## Phase ordering

0 → 1 → 2 → (3 optional). **Phase 0 alone clears the current false positives**
(silent-on-union). Phases 1–2 add real narrowing; Phase 3 adds the reciprocal
precision. Stop after any phase and the tree is still correct.

## Non-goals

- No general assignability / type-mismatch checking.
- No numeric-range or exhaustiveness narrowing.
- No nested discriminant paths (`r.a.kind === ...`) — single-level member only.
- Literals never become a first-class kind.
