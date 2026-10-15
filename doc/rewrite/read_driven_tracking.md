# Read-driven tracking

A var is tracked because reactive code reads it, not because someone declared it. `TRACKED(T, v)` is gone from hand-written code
(`banned_outside` in `tools/ci/lint_scopes.toml` allows it only in `code/engine/_generated/` and the macro's own file).

## The tracked set

`analyze gen auto_tracked` (`tools/analyze/src/gens/auto_tracked.rs`) writes `code/engine/_generated/auto_tracked.dm`. A `(declaring type, var)` is in it when:

1. **Reactive code reads it.** `gens/deps.rs` collects every var read by a draw, stat input or formula, requirement, condition, `ui_data`/`ui_from` output,
   capability entry and Life presentation reaction, through the closed interprocedural walk (virtual calls are the union of the overrides). It also takes every
   `nameof(v)` a CAPABILITIES block names (a `when` gate, a stat input, an `every(when =)` gate, a toggle), and reads through a context hop (`actor`, `held`,
   `target`) or a hop that crosses a non-relation var. A var must also be written somewhere (a var no proc writes is constant).
2. **Or it is written through a setter.** A `set_v()` / `add_v()` call whose receiver type is that type or a related one (`typed_set_calls`) keeps the var tracked
   after the last reader goes. The call scan types unqualified calls, `src.`, parameters and typed locals; when none is typed it falls back to the name if no
   unrelated type owns a hand-written `set_v`. `[lint.auto_tracked.lists] include` names the few vars whose callers reach them through an accessor.

Left alone (`DQ_AUTO_REPORT=1 analyze gen auto_tracked` lists them): built-in vars (they publish from engine choke points), `static`/`const`, non-`/datum`
types, profile records (`TRACKED_DATA`), engine-internal state, vars on an ancestor that is tracked, vars whose type or ancestor already defines `set_v`
(a subtype override that calls `..()` is fine), the `exclude` lists, and Rust-owned values (`watched()`).

The setter has the semantics `TRACKED` had: `TRACKED_UNCHANGED` compare (null differs from 0), write, `tracked_changed(src, "v")`, and it registers
`__setter_v`, so VV edits (`vv_edit_var`) go through it and publish. A list var gets `add_v`, `include_v`, `remove_v`, `set_v_at`, `clear_v`, `insert_v`,
`swap_v`, `cut_v` (`tracked_lists.dm`). Test-only types are emitted under the `UNIT_TESTS` guard. The inference never reads its own output, so it converges.

## Writes

The `tracked` lint (hard error, no baseline) rejects `v = x`, `src.v = x`, `O.v = x`, compound ops, `++`/`--` and list mutation outside the generated
setter. `analyze fix --apply [--tests]` rewrites them to `set_v(...)` / the list mutator; a write whose value is used (`(v = x)`, a `for` header) is
left for hand conversion. Decisions:

* **Initializers** (`var/x = 5`, `x = 5` in a type body) are defaults, not writes.
* **Construction.** A write to the instance's own var inside `Initialize()`/`New()` is not a change (nothing reads an object still being built) and stays raw;
  this also keeps the `init` ratchet, which fingerprints those lines. Writes to another object, or in `on_holder_init()`/`after_init()`, are judged normally.
  A merge-into-existing step in an `Initialize` moves to `after_init`.
* **Serializer.** It writes through `vars_write()`/the schema codecs, which publish; it is not a raw write the lint sees.
* **VV.** `vv_edit_var` calls the registered setter (`__setter_v`), else `vars_write()`, which publishes.

## Sweep and re-running it

`analyze fix --drop-declared --apply` deletes the plain `TRACKED(T, v)` lines the generator now covers (and those of vars nothing reads or calls); a line it
cannot cover is reported as KEEP and becomes a hand-written `set_v()` plus `SETTER(T, v)`. `analyze fix --apply` and `--tests` convert raw writes. Both are
idempotent, so after a merge run them again instead of hand-merging; then `analyze baseline --update` (or `--migrate` after taking master's baseline).
An `ALLOW(reads)` annotation that no longer triggers is deleted by the unused-annotation check.

## Lints that learned the generated set

`dx_reactive` and `derived_reads` read the generated file; `base_vars` counts `SETTER` as a home; `dx_reactive` treats a var no proc writes as constant.

## Cost

A setter is an unchanged-value compare plus a demand-gated `tracked_changed` (publishes only when something reads the key). The risk is write-heavy
vars that became tracked. Suspected hot paths (not measured): `canmove` (written on every Life tick and move through `update_canmove`), Life-tick mob vars
read by presentation reactions (`stat`, `lying`, `resting`, sight/hud flags), atmos machinery vars read by draws (`use_power`, `on`, pump/vent targets),
`heat`/`temperature`-style accumulators and `priority_overlays`/`dirty`-style flags rewritten per draw, and process loops of machines that write a var every tick
(`charge`, `timer`).
