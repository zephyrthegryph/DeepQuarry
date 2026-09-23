# Instance list audit (memlists)

A type-level `var/list/foo = list(...)` gives every instance its own list at
creation. This audit covers the type-level list vars left after wave 0
(MEM1–MEM9 in `fixes.md`) and records what was changed, what was kept and what
is left. The rules are in AGENTS.md §3a.

## How it was measured

`boot_memory` now reports `var_lists_total`, `var_lists_empty` and
`var_list_entries`: every distinct list held in an instance var of a datum or
atom after boot (built-ins such as `contents`, `overlays` and `verbs` are
skipped, and a shared list counts once). The `var_lists_top` detail gives the
top `type.var` holders. The numbers are from the minitest map
(`Virgo_minitest`, 94k instances, 7.5k objs, 15 mobs). The full map has several
times as many objs, so the savings there scale up.

The static scan found 1,383 type-level list declarations with an initializer
(1,473 counting typed `list/obj/foo` vars), plus about 12,000 subtype overrides
that assign a list, which also allocate per instance.

Classes: **a** constant table, made static or a getter; **b** usually empty,
made lazy; **c** rarely written, shared and copied on write; **d** genuinely
per instance, left alone.

## Changes, by impact

"Boot" is the minitest count of lists before the change. "Full map" is a rough
estimate.

| Type | Var | Class | Boot lists | Full-map est. | Change |
|---|---|---|---|---|---|
| `/datum/gas_mixture` | `reaction_results` | b | 8,759 | 30k+ | No longer created in `New()`; it is only built when a reaction fires. `LINDA_fire` handles null. |
| `/atom/movable` | `priority_overlays` | c | 3,782 | 30k+ | Every generic movable stored its emissive blocker in a one-entry list. A lone priority overlay is now stored bare; `add_overlay`/`cut_overlay`/`Destroy` handle both forms. |
| `/datum/integrated_io` | `linked` | b | 1,802 | 2k | Lazy; `LAZYOR`/`LAZYREMOVE`/`LAZYLEN` at every site. |
| `/datum/reagents` | `reagent_list`, `reagent_by_id` | c | 1,042 | 10k+ | Empty holders share one static empty list (`reagents_empty_list()`), so every `.len` reader still works. `add_reagent` calls `own_reagent_lists()`, and a holder goes back to the shared list when emptied. The four external writers (IV drip, medical stand, syringe, circuit) use the new `adopt_reagent()`, which also keeps `reagent_by_id` in sync. |
| `/obj/item` | `armor` | c | 821 | 15k+ | Interned by contents in `Initialize()` (`string_assoc_list`). `own_armor()` copies before a write, and every writer calls it: infective, material armor, accessory stats, rig seals, rig radiation shielding, mask toggle. |
| `/turf/simulated/wall` | `wall_connections` | c | 580 | 5k+ | The eager `list("0","0","0","0")` is gone (it was always replaced), and the computed corner states are interned with `string_list()`, so walls with the same shape share one list. Read through `get_wall_connections()`. |
| `/obj` | `req_access`, `req_one_access` | c | 51+ (firedoors alone) | 3k+ | Interned by contents in `/obj/Initialize` (`intern_access_lists()`). In-place clears (`LAZYCLEARLIST`) became `= null`, and the admin access viewer and airlock electronics copy before editing. |
| `/atom` | `atom_colours` | b | 1,126 | many | `update_atom_colour()` and `remove_atom_colour()` no longer allocate the 4-slot list just to read or clear colours. Atoms that really have a colour keep theirs. |
| `/datum/reagent` | `filtered_organs` | b | 246 | 1k+ | Base `list()` removed (the one reader was already null-safe). |
| `/obj/machinery/door/firedoor` | `tile_info`, `dir_alerts` | b | 255 (51 × 5 incl. nested) | 10k | `tile_info` (plus 4 nested lists, rebuilt on every check) is now proc-local, and examine reads it fresh. `dir_alerts` is lazy, allocated only while a direction is alarming. |
| `/datum/unarmed_attack` | `attack_verb`, `attack_noun` | c | 368 | same | Interned with `string_list()` in `New()`. |
| `/datum/hud_data` | `gear` (15 nested lists), `equip_slots` | c | ~920 | same | One table and slot list per type, shared in `New()`. |
| `/datum/techweb_node` | `unlock_ids`, `required_items_to_unlock`, `required_experiments`, `discount_experiments`, `experiments_to_unlock` | b | ~5 × nodes | ~1.5k | Lazy; `.len` became `length()`, and SSresearch uses `LAZYSET`/`LAZYADD`. |
| `/datum/design_techweb` | `reagents_list`, `unlocked_by` | b | ~2 × designs | ~2k | Lazy. |
| `/datum/gene/trait` | `conflict_traits` | b | 82 | 82 | Lazy. |
| `/datum/event_meta` | `role_weights`, `min_job_count` | b | 166 | 166 | Plain null; they are only iterated. |
| `/obj/item/camera_assembly` | `possible_upgrades` / `upgrades` | a / b | 76 | 700 | Static table and a lazy list. |
| 164 types | constant tables | a | ~1 per instance each | — | `var/static/list`, for vars with no writer, no subtype override and no mutation through a proc (`memlists-classify`). Examples: raider outfits, SDQL operators, firedoor `ALERT_STATES`, vore belly select messages, horoscope text, mob style tables. |

### Measured result (minitest boot_memory)

| Metric | Before | After |
|---|---|---|
| `var_lists_total` | 102,507 | 78,354 (-23.6%) |
| `var_lists_empty` | 26,996 | 12,968 (-52.0%) |
| `var_list_entries` | 436,726 | 406,200 (-7.0%) |

The instance count was unchanged (94,283 before, 94,475 after) and so was the Rust heap (13.8 MB). The runner read DreamDaemon's private memory as 0 MB, so there is no process memory figure. The full `dm-test` passed: 697 passed, 0 failed, 58 skipped.

## Kept (class d)

The lint allowlist (`tools/ci/instance_list_allowlist.txt`) has a "kept"
section:

- `/datum/internal_wiki/page/data`: every page fills it.
- `/datum/stack_recipe_list/recipes`, `/datum/radio_frequency/devices`: always
  populated.
- Lists that are now shared at runtime but are still declared with an
  initializer (item `armor`, hud `gear`, unarmed verbs): the eager allocation
  is dropped after interning. Removing it needs getters per subtype.

## Not converted (backlog)

- **Lighting**: `/datum/lighting_corner/affecting` (3,834) and
  `/datum/light_source/effect_str` (205) hold live data. Leave them.
- **Signals**: `_listen_lookup`, `_signal_procs` and `_status_traits` exist only
  when used.
- **Snacks** `nutriment_desc` (subtype overrides on every snack): class c, but
  the list is passed as reagent `data` and may be stored by reference, so
  sharing it needs `mix_data` checked first.
- **Species** (~54 datums × ~25 lists: `has_organ`, `has_limbs`,
  `unarmed_types`, `genders`, discomfort strings and more): per-subtype
  constants. They want getters, but species code is shared with the body
  rewrite.
- **Vending** `products`, `contraband`, `premium`, `prices`: about 100 vendors
  on the full map. The product tables are consumed at init and could be nulled
  after it. (`log`, `ads_list` and `slogan_list` are now lazy.)
- **Mobs** (98 lint entries; 15 mobs at boot): `languages`, `mutations`,
  `organs*` and similar, all per-mob state.
- **Guns** `burst_accuracy`/`dispersion` `list(0)`: constant defaults, and only
  a handful at boot.
- The remaining ~1,180 declarations on rare types are allowlisted as a
  baseline. The lint stops new ones.

## For other active areas (listed, not edited)

- **M1a (atmos adjacency)**: `atmos_adjacent_turfs` is the largest list holder
  (26,194 at minitest boot, one per turf including `/turf/space`). Space and
  unsimulated turfs could share an empty list or stay null.
- **Atmos pipes**: `rust_pipe_port_ids` (648) and `pipe_network`
  `leaks`/`gases`/members.
- **Material composition rewrite**: `matter` (781 at boot, on every item) and
  `/datum/design_techweb/materials` were left alone as instructed.

## For the medical session

These are in `code/modules/body`, `medical`, `organs`, `surgery` and protean,
and were not edited here:

- `/datum/reagent/treatment_tags` (body/treatment.dm): subtype overrides give
  every live reagent datum its own table (246 at minitest boot, the same as
  `filtered_organs`). Intern it in `/datum/reagent/New()` with
  `string_assoc_list()`, which is read-only by design.
- `/obj/item/organ`: `autopsy_data`, `trace_chemicals`,
  `will_assist_languages`, `assists_languages`, `target_parent_classes` should
  be lazy, and `target_parent_classes` is a constant table.
- `/obj/item/organ/external`: `children`, `internal_organs`, `implants`,
  `markings` should be lazy for limbs without them.
- `/obj/item/organ/internal/eyes/eye_colour`: a per-instance colour list.
- `/datum/robolimb`: `species_cannot_use`, `species_alternates` should be
  static.
- `/datum/surgery_step/excludes_steps`: static or a getter.
- `/obj/item/organ/internal/lungs/replicant/mending/repair_list`,
  `nano/refactory/materials`, `augment/armmounted` tool lists: constant
  tables.
- Protean rig module `armor_settings`: constant table.
- The `/mob/living` organ lists in `mob/living/organs.dm` (`internal_organs`,
  `organs_by_name`, ...) are eager on every living mob.

## Lint

`tools/ci/instance_list_lint.py` (in `run_linters.yml`, "Check Instance List
Allocation") flags any type-level list var with an initializer (`list(...)`,
`new/list`, `new()`, `list/x[N]`) that is not in
`tools/ci/instance_list_allowlist.txt`. It also rejects entries without a
reason and entries that no longer match anything. At the time of writing it
flags 1,308 declarations, all of them allowlisted: 11 kept, 19 medical, 98 mob
and 1,180 baseline.

## Hazards introduced

Shared lists must not be edited in place. Admin VV edits of an interned
`armor` or `req_access` list would change every object sharing it. Code paths
that edit these lists now copy first.
