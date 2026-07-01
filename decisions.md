# Decision log

Durable "why we chose X" records. Completed work lives in git history and
`CLAUDE.md`; forward-looking work lives in `plan.md`. This file is for choices
that are easy to second-guess later — especially the things we deliberately did
*not* do.

---

## Won't-do: retire `binderIn` by having the scope walker record decl offsets

**Decision.** Keep `definition.uc`'s `binderIn` / `localScopeDef` as the local
go-to-definition resolver. Do **not** replace them with a query against the
type scope map.

**Why.** It looks like a lookup swap but isn't semantically equivalent:

- `binderIn` is *whole-region*; the type scope is *positional* (`advanceScope`
  adds a declaration to the scope only after its own statement). Go-to-definition
  today resolves forward references — a call above a hoisted `function`
  declaration, and a use of a `let` before its declaration both resolve. A
  positional scope-map query returns `null` for both → regression.
- A faithful version needs a *separate hoisted decl map* replicating five
  visibility models — block = whole-block, function = params, for-in = loop
  var(s), catch = param, template `statement_tag` = whole-tag — across ~10
  walker variants (`walkBlock`, `walkFn`, `walkForIn`/`walkForInAlt`,
  `walkForStmt`/`walkForAlt`, `walkTry`, statement-tag threading).
- **Local go-to-definition inside template / alt-form bodies is untested**, so
  that surface would be unguarded during the change.

It is a lateral change (moves ~90 lines, adds a cached artifact + query API).
The one real benefit — a single source of truth for "what binds a name" — is
already delivered by the 8-shape binder-identity property test, which fails if
`binderIn` drifts from the grammar. Net risk > benefit for a hot-path data
structure with an untested edge.

**Guardrails in place.** The forward-reference behaviors are locked by unit
tests (hoisted forward function ref, use-before-`let`), and the binder-identity
property covers let / block / for-in / two-var for-in / C-for / catch / param /
arrow shapes.

**Revisit if.** We add join-point widening or otherwise make the type scope
hoisted anyway, *and* local template go-to-definition gains real test coverage.

---

## Won't-do: unify `deprecatedNames` with `resolveDoc`'s resolution order

**Decision.** Keep `deprecatedNames` as an independent candidate-name prefilter
for the deprecated-usage diagnostic, even though its comment notes it mirrors
`resolveDoc`'s resolution order.

**Why.** A true fix unifies a name-set prefilter with a per-node resolver — two
structurally different shapes — and ends up larger than the gate itself. The
only real risk is drift causing the gate to *lose* diagnostics (it can never add
false ones), and that is already guarded by a positive-oracle property test that
asserts the gate flags all-and-only references to deprecated names.

**Revisit if.** The gate and `resolveDoc` are observed to disagree in practice,
or the resolution order grows complex enough that keeping two copies in sync
becomes a maintenance hazard.

---

## Resolved review items (for provenance)

The code review that produced these decisions also surfaced work that is now
done; kept here only so the trail isn't lost:

- Correctness (5 bugs + rest-param gd): `867a235`, `2f0fa14`
- Edge + property tests for require / legacy-exports / deprecated-gate / local-gd: `304edb1`
- Performance — linear `buildLineTable` + batched field docs (fw4.uc 67ms → 7ms): `1509806`
- `stringLiteralText` dedup + orphaned-comment move: `ba06f91`
- Go-to-definition regression tests (forward function ref, use-before-`let`): `fcef43c`
