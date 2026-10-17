# Decision log

Durable "why we chose X" records. Completed work lives in git history. This
file is for choices that are easy to second-guess later — especially the things
we deliberately did *not* do.

---

## Won't-do: retire `binderIn` by having the scope walker record decl offsets

**Decision.** Keep `definition.uc`'s `binderIn` / `localScopeDef` as the local
go-to-definition resolver. Do **not** replace them with a query against the
type scope map.

**Why.** It looks like a lookup swap but isn't semantically equivalent:

- `binderIn` is *whole-region*; the type scope is *positional* (`advanceScope`
  adds a declaration to the scope only after its own statement). Go-to-definition
  today resolves references to a *later* declaration in the same region — a use
  of a `let` before its declaration (valid ucode; the name reads as null until
  init) and, more leniently, a call above a `function` declaration (ucode does
  NOT hoist, so that call is a runtime error, but gd still points at the sole
  declaration). A positional scope-map query returns `null` for both → the
  use-before-`let` case is a real regression. (ucode has no hoisting, so the
  function case is UX-nicety, not a correctness requirement.)
- A faithful version needs a *separate hoisted decl map* replicating four
  visibility models — block = whole-block, function = params, for-in = loop
  var(s), catch = param — across ~9 walker variants (`walkBlock`, `walkFn`,
  `walkForIn`/`walkForInAlt`, `walkForStmt`/`walkForAlt`, `walkTry`).
  (Templates no longer add a fifth: since the grammar models a template as
  ucode's statement stream, its code nests exactly like a script's.)
- **Local go-to-definition inside template / alt-form bodies is untested**, so
  that surface would be unguarded during the change.

It is a lateral change (moves ~90 lines, adds a cached artifact + query API).
The one real benefit — a single source of truth for "what binds a name" — is
already delivered by the 8-shape binder-identity property test, which fails if
`binderIn` drifts from the grammar. Net risk > benefit for a hot-path data
structure with an untested edge.

**Guardrails in place.** The forward-reference behaviors are locked by unit
tests (later function declaration, use-before-`let`), and the binder-identity
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

## Deferred: chunk the synchronous `loadWorkspace` at startup

**Decision.** Keep the `initialized` handler loading the whole workspace
(`workspace.loadWorkspace`) in one synchronous pass on the event loop. Do **not**
(yet) split it into N-files-per-turn chunks driven by `workspace/diagnostic/refresh`.

**Why the obvious fix is wrong here.** Chunked loading leaves a *partial DAG
window*: between chunks, the DAG knows some files and not others. The
interactive cross-file features (definition, hover, completion) resolve targets
straight out of the DAG and, unlike `unknown_import_symbols` (which force-loads a
missing target via `dag.addFromDisk` before deciding), they simply return `null`
on a miss. So during a chunked load they would intermittently return "no
definition / no hover" for symbols in not-yet-loaded files — and the e2e suite,
which opens a file and immediately queries, would go non-deterministic.

A correct chunked load therefore needs the *reads* to be lazy too: every
cross-file DAG lookup must self-heal (force-load the target on miss) the way
`unknown_import_symbols` already does, so a partial window is invisible to
callers. That is a central change to DAG read semantics, not a change to the
loader — and it is the real prerequisite, not the chunking itself.

**What we did instead.** The blocking package-manager probes (the other startup
cost) already run off the event loop in a `uloop.task` (`platform.initAsync`),
which is safe because their output is a small serializable index dict. The DAG
load can't use `task()` the same way: its output *is* the large shared state plus
native tree-sitter handles, which don't survive the pipe.

**Revisit if.** We make cross-file DAG reads uniformly lazy/self-healing, at
which point chunked startup becomes a safe, mechanical follow-up.

---

## Won't-do: builtin call validation (argument count / type / coercion)

**Decision.** Do **not** add a diagnostic that validates call sites against
declared signatures for argument *count* or argument *type*. It is not
precision-safe in ucode.

**Why.** The premise ("the typed `declarations/*.d.uc` files hold the raw
material") is true but insufficient: ucode's runtime tolerates almost every
mismatch a signature check would flag, so the checks would fire on code the
interpreter runs without error. Verified against `ucode -e`:

- **Arity underflow** — a missing argument is filled with `null`, not an error.
  `f(1)` where `f(a,b)`; `substr("hi")`; `math.abs()`; `length()`.
- **Arity overflow** — extra arguments are ignored. `f(1,2,3)` where `f(a)` → `1`;
  `substr("hello",1,2,3)` → `"el"`.
- **Type mismatch** — arguments coerce, they don't throw. `math.abs("hello")` →
  `NaN`; and even structured values coerce: `math.abs([1,2])`, `int([1,2])`,
  `math.sqrt({})` all → `NaN`; `substr([1,2,3],1)` and `length(5)` return quietly.

The only builtins that *throw* do so on the specific runtime *value*, not on
anything a signature encodes: `require("nonexistent")` (module name), `json("not
json")` (malformed literal), `json()` (throws because `null` is neither string
nor object). None is provable from arity or declared type without guessing the
value, so a static signature check can't reach them without false positives.

This is a general lesson applied to a *feature*: the
grammar and declarations describe a superset of what the language enforces, so
"the data exists" never implies "the check is true." The one call-shaped check
that survived this bar — the printf/sprintf format checker — did so because it is
grounded in observably-wrong behavior, not signature matching; the provable call
errors that remain (`not-a-function`, unknown module member, null dereference)
are already covered by existing diagnostics.

**Revisit if.** A future ucode gains a strict mode that actually enforces arity or
argument types at runtime — then the check would describe real errors and the
declaration data is ready for it.

---

## Resolved review items (for provenance)

The code review that produced these decisions also surfaced work that is now
done; kept here only so the trail isn't lost:

- Correctness (5 bugs + rest-param gd): `867a235`, `2f0fa14`
- Edge + property tests for require / legacy-exports / deprecated-gate / local-gd: `304edb1`
- Performance — linear `buildLineTable` + batched field docs (fw4.uc 67ms → 7ms): `1509806`
- `stringLiteralText` dedup + orphaned-comment move: `ba06f91`
- Go-to-definition regression tests (forward function ref, use-before-`let`): `fcef43c`
