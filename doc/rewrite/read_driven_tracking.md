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

## No holes (October 2026)

`untracked_inputs` and `sem/reads` are hard bans with no baseline. What closed them:

* **Flyweights.** A hop through a var whose declared type is a flyweight (`FLYWEIGHT_TYPES`, now including `/datum/material`) is not followed, and what a flyweight holds is constant.
* **Hops are findings where something is read through them.** A bare read of an object var (`if(cell)`, `return tank`) is the var's own tracked read; `cell.charge` or `cell.check_charge()` through a var that is not a declared relation is `hop_not_relation`. Declare the var a `ref_one`/`ref_many`.
* **Built-ins.** A turf's own `x`/`y`/`z`, `L.len` on a list var, `type`/`parent_type` and `gc_destroyed` are not inputs; a mob's `client` and `key` publish with `ckey` (`ckey_changed()`); `contents` is read through `contents_count()` / `contents_of()`, which stand for `SLOT_OCCUPANCY_KEY` (the ledger publishes it).
* **Memoized registries** (`PROC_SUMMARY(/proc/x)`: the icon manager, the decl repository, the material registry, the requirement interner, a lazily built overlay table) read no entity state; a shared image is a `look_cached_image()` or a shared cache, not a global list.
* **Sampling.** What cannot be tracked (the map's level lists, whitelists and ban lists, accounts, a profile record) is wrapped in `read_once()` where it is asked: the walk mutes it, and a menu that asked is rebuilt on each read. `git grep read_once` is the list; a new one needs a reason in the line. A draw, a stat contribution or a STAT formula never samples: `untracked_inputs/sampled_in_look` is a hard ban on a `read_once()` anywhere those reach, because a look made from a sample goes stale.
* **Visual built-ins.** An atom's `color`, `alpha`, `layer`, `plane`, `pixel_x`/`pixel_y`/`pixel_w`/`pixel_z`, `appearance_flags` and `gender` are `SETTER()`-registered (`code/game/atom/atom_visual.dm`): written through `set_color()`, `set_alpha()`, `set_layer()`, `set_plane()`, `set_pixel_x()`, `set_pixel_y()`, `set_pixel_offset(x, y)`, `set_appearance_flags()`, `set_gender()`, read tracked by a draw. The look applies its own through `look_set_*()`. `analyze fix --apply` converts the raw writes. A thing in a container reads through the `loc` hop only one step from the holder, so a draw that needs the wearer or the garment an accessory is on takes it as a parameter or reads a declared relation (`apply_blood(standing, wearer)`, `has_suit`). `atom/flags` stays untracked (lifecycle bits change inside a draw): an open-by-flag container publishes `REAGENT_OPEN_FLAG_KEY` from `set_open_by_flag()` and a draw reads `open_by_flag()`.
* **Drift.** In a test build the REFRESH DRIFT audit runs on every entity the strict staleness checker checks (`staleness_check_drift()`), not only on the sweep's budget.

## Windows (October 2026)

A window host's `ui_data(A)` is reactive code like a draw: `gens/deps.rs` counts every var it reads (inherited and implicit windows included, `code/modules/tgui/modules/` too), so
the var is tracked and written through its generated setter, and the host's open windows are pushed after a write (`ui_push.dm`). `untracked_ui_read` is a hard ban with no
exemption list. A ui read is fine when the var is tracked, a stat, a derived value or a declared relation (`ref_one`/`ref_many`/`owns_one`/`owns_many`, `link()`), or when nothing
writes it (a `static`/`const` var, or one no proc writes outside a setter and no `set_v()` call names). A hand `set_v(...)` with another meaning blocks the generated setter (rename it,
for example `show_temp()`); a hand setter that is a real setter publishes with `tracked_changed()` and is registered with `SETTER(T, v)`. `dq_ui_outputs_swept_*` pin the refresh.
