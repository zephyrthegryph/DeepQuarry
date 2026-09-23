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

## Pass 2 (memlists2)

Pass 2 cleared the backlog. Every declaration that was in the baseline section
of the allowlist is now converted or classified with its own reason.

### Measured result (minitest boot_memory)

Both runs are on `Virgo_minitest`, one before and one after, from the same
tree (the base run used the tree at `0786dbab42`).

| Metric | Before | After |
|---|---|---|
| `var_lists_total` | 78,376 | 66,385 (-15.3%) |
| `var_lists_empty` | 12,968 | 5,176 (-60.1%) |
| `var_list_entries` | 406,400 | 350,620 (-13.7%) |

The instance count was unchanged (94,506 after) and no runtimes were logged.
The full map (Southern Cross) boots, but its `boot_memory` census did not
finish inside the runner's time limit, so there is no full-map number. The
first full-map boot did find eight null-list runtimes, which are fixed.

### Changes

| Area | Class | Change |
|---|---|---|
| Species datums | c / b | 11 per-subtype tables (`has_organ`, `unarmed_types`, `genders`, `assisted_langs`, discomfort strings, `secondary_langs`, `inherent_verbs`, `default_emotes`, `speech_sounds`, `species_component`, shapeshifter `valid_transform_species`) are shared per type in `share_type_tables()`, called first in `New()`. `give_numbing_bite()` now assigns a new `unarmed_types`. `env_traits` and `food_preference` are lazy (`LAZYADD`/`LAZYREMOVE`/`LAZYOR` in the trait code); `skin_overlays` (unused) and `species_language` (never read as a list) lost their lists. `has_limbs` stays per copy: organ creation writes `"descriptor"` and `"has_children"` into its nested lists. `traits` stays per copy (genes `Add`/`Remove` it). |
| Vending | b / c | `products`, `contraband`, `premium` and `prices` have no initializer and are dropped after `build_inventory()` (hydroseeds too). The default refill table is the products list itself, not a copy, and identical refill tables are shared (`share_refill_table()`, keyed by type and contents). `product_records` stays per vendor; C9 turns stock into slots. |
| Vore bellies | c | 49 message tables and `generated_reagents` are shared per belly type in `share_default_tables()`, called from `New()` so callers that customise a new belly still win. The legacy `/datum/belly/copy()` assigns copies. |
| Guns | b | `burst_accuracy` and `dispersion` default to null (0 for every shot); readers use `LAZYACCESS(...) \|\| 0`. |
| 677 rare-type lists | b | Lazy. Every reader and writer was rewritten with `LAZYADD`/`LAZYREMOVE`/`LAZYOR`/`LAZYSET`/`LAZYADDASSOC`, `LAZYACCESS`, `length()`, `LAZYCOPY` (new), `LAZYFIND`, `DEFAULTPICK`, or `\|\| list()` where the list goes to TGUI or JSON. `english_list()`, `pick_mobless_turf_if_exists()` and `has_all_reagents()` accept null. |
| 27 constant tables | a | `var/static/list`: no writer, no assignment, no subtype override (event exclusion lists, organ printer products, multitool/RMS modes, contraband scanner list, holodeck programs, ...). |
| Interned by contents | c | New `intern_list()` (JSON-keyed cache for read-only lists of any shape): sprite accessory `species_allowed`, robot `hat_offset`, drug message tables, item `attack_verb` and `tool_qualities`, and `atom_colours` (copy-on-write in `add_atom_colour()`/`remove_atom_colour()`). Structure `connections`/`other_connections` go through `string_list()`, as wall connections did in pass 1. |
| Unit-test probes | d | Six new lint hits from other branches (test fixtures, and the interaction resolver) are allowlisted. |

### Snack `nutriment_desc`: not shared

`add_reagent()` passes `nutriment_desc` as the nutriment's `data`, and
`/datum/reagent/initialize_data()` stores it by reference, so each snack's list
already is its nutriment's taste data: one list per snack either way.
`/datum/reagent/nutriment/mix_data()` then edits that list in place
(`data[taste] += ...`, `data -= taste`). Sharing the snack table would make
every snack's taste data one list. It could be shared only with copy-on-write
in `mix_data()` plus an audit of every other writer of reagent `data`, and even
then the saving is zero: the reagent needs its own list once tastes mix. It is
kept as class d.

### What was kept, and why

The allowlist's kept section gives the reason on every line. The main groups:

- **Per-instance state (d)**: stock, queues, logs, board state, access lists
  (where an empty list and null differ for access checks), fixed-size
  `list/x[N]` tables, lists written through an alias (`var/list/L = member`
  then `L[k] = v`), and lists that code tests for truth where the negative
  branch does something different.
- **Singletons (d)**: subsystem, controller, registry and decl lists. One
  instance, so there is nothing to share.
- **Read-only per-subtype tables on rare types (c)**: 47 tables with subtype
  overrides. A getter would share them; not worth it for the instance counts.
- **Generic names (d)**: `data`, `contents`, `fields`, `name`, `log`, `errors`
  and similar have hundreds of ambiguous call sites; the lists are live state.
- **Never instantiated**: `/datum/belly` (legacy; nothing creates it or calls
  `copy()`). Delete the type rather than convert it.

### Still open

- The remaining top holders at minitest boot belong to other areas:
  `atmos_adjacent_turfs`, lighting (`affecting`, `effect_str`, `light_sources`),
  reagent holders, `internal_wiki` page `data`, `rust_pipe_port_ids`, `matter`,
  `treatment_tags`, signal lists (`_listen_lookup`, `_signal_procs`).
- Turf `decals` (one list of images per decorated turf) could be interned by
  appearance, but images are not JSON-able; it needs its own cache.
- Tank and clothing `sprite_sheets` are edited in place (`LAZYSET` in space
  suits), so they cannot be interned without copy-on-write there.
- The 47 class-c tables could become getters if their types become common.
- `code/modules/medical/book/reagents_tab.dm` got one read fix
  (`LAZYACCESS(CR.required_reagents, RQ)`) because reaction tables are lazy
  now; nothing else in the medical area was edited.

## For other active areas (listed, not edited)

Pass 2 also lists here: omni filter/mixer and trinary filter device lists,
`pipeline/leaks`, `SSair` shutoff queue and LINDA `hot_group/spot_list`
(atmos); `design_techweb/materials` (composition); blood, mucus and vomit decal
`viruses` and drip `drips` (medical); the interaction resolver's `available`
and `blocked` lists (interaction work).

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
reason and entries that no longer match anything. After pass 2 it flags 589
declarations, all allowlisted: 455 kept (class d per-instance state, class c
read-only per-subtype tables, or shared at runtime), 17 owned by other areas,
19 medical and 98 mob. The baseline section is gone.

## Hazards introduced

Shared lists must not be edited in place. Admin VV edits of an interned
`armor` or `req_access` list would change every object sharing it. Code paths
that edit these lists now copy first.

Pass 2 adds more shared lists under the same rule: species tables
(`share_type_tables()`), belly message tables (`share_default_tables()`),
vending refill tables, and everything passed through `intern_list()` or
`string_list()` (`atom_colours`, structure `connections`, item `attack_verb`
and `tool_qualities`, sprite accessory `species_allowed`, robot `hat_offset`,
drug messages). Writers assign a new list.

Lazy lists change one thing besides memory: an empty list is true in DM and
null is not, so checks like `if(!L)` that were dead code become live. Pass 2
reviewed the truth tests on converted vars. Where the negative branch did real
work (hard drive `store_file()`, the chat client, targeted spells, robot belly
tables) the check was fixed or the list was kept eager.
