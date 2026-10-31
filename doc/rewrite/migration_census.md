# Migration census (2026-10-24)

An honest count of what is left between master and the design in `final_api.html`. Sources: `bash tools/ci/legacy_form_counts.sh`
(no non-zero row of a banned form) and the non-comment rows of each `tools/ci/*_baseline.txt`, as of `origin/master` 53da4e7b13. Effort is in
**waves** (one lane, roughly 20-40 files); these are estimates from site counts, not measurements. Per-file move status is
`bash tools/ci/move_candidates.sh [--summary]`, not this document.

## Verdict

- Every hard-banned legacy form is at zero, and `legacy_form_counts.sh` reports no non-zero row (its `CHANGE_` hits were an overmap macro and a doc-comment placeholder, now renamed). The doc §17
  replacements for the banned forms have landed and their callers are converted; what is left is **sites of forms whose replacement has
  landed but whose callers are not all converted** (init, base vars, stored refs, native ref writes, a slice of ref text).
- `system_boundary` is empty (5 -> 0): see the next section. `stored_refs` fell 107 -> 13.
- Of the live ratchets, three are real migration (init, base_vars, stored_refs; native_ref_write and decl are at zero), `ref_text stored` is migration
  (relations D9), two are mostly code quality (`untyped`, `ref_text ref_macro`), and `op_order` and `escape_hatches` are small keeps.
- Files have started to move: `code/content/` already holds `client`, `clothing`, `medical`, `power` and `projectiles` (583 of 7,114 `.dm`
  files are under `content/`, `library/` and `domains/`). `food` and `modular_computers` (migrate/file-moves-1) are not on `origin/master` yet.
  Which old files can still move as a pure `git mv` is `tools/ci/move_candidates.sh`; the old per-folder figures here were dropped as stale.

## system_boundary (done)

| Rule | Was | Now |
|---|---|---|
| B1 `SSx.<var>` outside the owner | 7 sites in 5 files (baseline rows: 1+1+1+3+1) | 0 |

Callers now use the system's `api.dm`: `SSflight.destination_by_id()`, `index_destination_target()`, `unregister_vessel()`;
`SSshuttles.queue_sector_init()`; `SSmapping.set_engine_loader()`; `SSpersistence.load_paintings()`, `reset_unpicked_paintings()`.
`/datum/system/flight/vessel_by_ship` was a REF-text map that duplicated `ship.flight_vessel_id` (set together, never cleared apart), so it
is deleted instead of wrapped; this also removed stored REF sites. The paintings `Initialize()` body moved into a named
`load_database()`: ten `init_lines` rows left the baseline and one (`load_database`) took their place, a net shrink of nine.
The baseline file is header-only: the lint's policy is custom ceilings, and a rule with no ceiling fails its next site, which is the hard ban
(the same shape as the other empty baselines). `lint_scopes.toml` has no separate switch for it.

## The ratchets

Kind: **M** migration form (doc §17/§19) or **Q** code-quality ratchet. "Landed" says whether the replacement exists on master.

| Ratchet | Count | Files | What it counts | Kind | Replacement | Landed | Effort |
|---|---|---|---|---|---|---|---|
| `init` | 320 (308 `init_lines` + 12 `world_reads`) | 100 | Each imperative line in an `Initialize()` override, and `GLOB.`/`range(`/`START_PROCESSING` reads at init | M (§6, §17) | `starts =`, `rolls()`, `param()`, `on_holder_init(A)`, `after_init()`, `setup(PROC_REF(x))`, `membership()` | yes | About 6 waves. About 5.6 lines per file; contents, timers and registration are mechanical. Per-instance state no form names stays under `ALLOW(init/CODE)`. |
| `ref_text` | 326 = 250 `ref_macro` + 76 `stored` | 226 | `ref_macro`: a `\ref[...]` text in code (mostly Topic hrefs). `stored`: a `REF()` result kept in a var, list or key | `stored`: M (relations D9). `ref_macro`: Q | `ref_token()` in data, `ref_one(weak = TRUE)` in content; for hrefs `interface()` + `ui_act` | yes | `stored`: 2 waves. `ref_macro`: do not convert by hand; it falls as each Topic window becomes `interface()`/`op(ui_act)`. |
| `entity_ids` | 41 = 29 `counter_id` + 12 `ref_key` (seeded 2026-10-27) | 32 | `counter_id`: an id minted from a counter named as an id (`next_*id++`, `*uid++`). `ref_key`: a `REF()` text embedded in a list key | M (relations D9a, one handle) | `ref_token(D)` / `resolve_token(h)`; a player-facing serial that is data keeps its site with `ALLOW(entity_ids)` | yes | small: one site at a time; the panel registries (`GLOB.dq_*_panels`) convert together with their writers |
| `base_vars` | 270 = 263 `base_var` + 7 `list_init` | 144 | A var declared on a base type (`/atom`, `/obj`, `/mob`, ...); an instance `= list()` | M (§4/§7, base_vars proposal) | Trait block, profile record, HUD datum, owning domain, `TRACKED`/`STAT`, `sparse(T, x)`, cooldown table, relation | yes | Largest and most design-bound: 8-10 waves. Each var needs a home decision; `analyze base-vars-dead` finds the free ones (delete) first. |
| `untyped` | 205 = 198 `call` + 7 `typed` | 316 | An untyped `var/x` that a proc assigns an atom/datum (or an uncheckable call result) | Q (closes a hole in `stored_refs`, relations D8) | Declare the type, then a relation (`ref_one`/`owns_one`/`weak = TRUE`) or a non-reference type | yes | About 6 waves, mostly mechanical typing; the 451 `call` rows need a look at what the call returns. Many vanish when the owning file converts. |
| `stored_refs` | 13 = 9 `list` + 4 `var` | 12 | A typed atom/datum var, or a list filled with atoms/datums, that no relation declares | M (§6 "Storing references") | `ref_one`/`ref_many`/`owns_*`/`links()`/`slot()` | yes | 3-4 waves; each is a lifecycle decision (who clears it), so slower per file. |
| `native_ref_write` | 0 | 0 | Raw `+=`/`-=`/`.Add()` on `vis_contents`, `client.images`, `client.screen` | M (relations D11) | `vis_add`/`vis_remove`, `client_screen_add`/`_remove`, `client_images_add`/`_remove` (`code/engine/present/native_ends.dm`) | yes | 2 waves, near-mechanical; concentrated in `_onclick/hud`, pAI HUD, smite, GPS. Then it becomes a ban. |
| `decl` | 0 | 0 | Work in `Initialize`/`on_destroy` that a lifecycle declaration does | M (declarative lifecycle) | `starts =`/`owns_one`; slot spill / `on_destroy` forms | yes | Under one lane. |
| `escape_hatches` | 123 ceiling units (`init_allow` 36, `usr_allow` 5, `usr_content` 82) | ceilings only | Kept `ALLOW(init/...)` overrides, kept `usr` sites, every `usr` outside engine and verbs | Q | Per-instance init stays where no form fits; pass the actor in instead of `usr` | partly (`init_allow` is a justified-keep list, not all debt) | `usr_content` 82: about 2 waves. `init_allow` falls with `init`. `usr_allow` 5: trivial. |
| `op_order` | 1 ceiling = 15 `relative_priority` | ceilings only | Hand-written `priority(above(...))`/`below(...)` | Q | `click_order()` on the bundle that owns both ops | yes | One lane. |
| `system_boundary` | 0 | 0 | See above | M (§2) | `api.dm` procs | yes | Done. |

## What blocks each remaining ratchet

- `ref_text`: `stored` rows keep an identity-key REF (a text key standing for an object) in a var, list or key; converting them needs a design
  decision on identity-key refs (relations D9) before any hand conversion. `ref_macro` is not hand-converted: it falls as each Topic window
  becomes `interface()` + `op(ui_act)`.
- `base_vars`: the remaining vars are relation-held (they need a `ref_one`/`owns_*` home and a lifecycle call) or on hot paths where moving
  the var changes cost; the dead ones are already gone (`analyze base-vars-dead`).
- `untyped`: 198 of 205 are `call` rows, where the assigned call's return type is not known; they need analyzer inference, not edits.
- `stored_refs` (13): `code/ATMOSPHERICS/rust_pipenets.dm`, `xgm_compat.dm`, `_global_vars/__unsorted.dm`, `_helpers/global_lists.dm`,
  `datums/containment/latency_policy.dm`, `domains/heat/heat_entries.dm` (2), `game/machinery/machinery.dm`, `modules/client/client defines.dm`,
  `modules/mob/living/life/living_systems.dm`, `.../silicon/robot/robot_upgrade_detection.dm`, `modules/tgs_commands/vorestation.dm`,
  `modules/tgui/external.dm`. Each is a who-clears-it lifecycle decision.
- `init`: per-instance setup no declared form names; the rest is mechanical (`starts =`, `after_init()`, `on_holder_init`).

Open forms with no ratchet (AGENTS.md §3b): none; the `prompt_flow()` hits in the old tree are the kept DB re-run machinery, not prompts.

Total of the rows counted above: 320 + 326 + 270 + 205 + 13 = 1,134, plus the escape-hatch ceilings (`escape_hatches` baseline 3 rows; ceilings not recounted). `native_ref_write` and `decl` baselines are empty.

## Method

- Baseline rows are the non-comment lines of `tools/ci/*_baseline.txt` (first tab column is the rule). To refresh: re-run
  `bash tools/ci/legacy_form_counts.sh`, recount the baselines, and use `tools/ci/move_candidates.sh` for moves.

## Move blockers: defines, baseline, systemowner (2026-10-30, branch migrate/defines-baseline)

`bash tools/ci/move_candidates.sh` before: 1,873 dirty files in the old tree. After this lane: 4,327 old-tree files, 2,656 clean, 1,671 dirty
(reasons overlap: oldform 779, baseline 633, allow 443, toolref 263, systemowner 20, defines 3).

**defines (done, 3 left).** 296 files moved from `code/__defines/` to `code/defines/{engine,library,host,base,content}/` (the old
`__defines/engine/` is `code/defines/engine/declare/`; `README.md` is `code/defines/README.md`). The `.dme` keeps every file's compile slot
(`tools/build/dme_moves.txt`), so `move_equiv.sh` reports the production world EQUIVALENT; the test world differs only in the one string
`font_awesome_icons` unit test reads with `file2text` (its path moved; the test passes). The analyzer, `lint_scopes.toml`, codemods, TGS
workflow and lane-ready lists follow (`scopes::is_defines`, and the synthesized partial-model manifest now orders macros by `.dme` slot, which
path order no longer reproduces). Still in `code/__defines/`: `announce.dm`, `plants.dm`, `rust_g.dm` (named by `tools/dm-health/baseline.json`,
off limits here) and the gitignored generated `verdigris/` bindings (their generator paths are in `tools/build`).

**baseline (636 files still named; 627 after counting only `.dm` rows).**
- `tools/ci/ending_causes_snapshot.txt` named 680 files: made path-independent (rows are verb, proc, statement; `ending_sites.py --check`
  compares as a multiset). Those files are clean now.
- `tools/dm-health/baseline.json` (off limits to this lane) still names 606 files whose only baseline reason is that file: its rows are
  keyed by path, so a move must rewrite them in the move commit (as `file-moves-8` did). Needs the owner to make the key path-independent
  or to allow move agents to rewrite its paths.
- Live debt, no stale rows (`analyze baseline --update` removed nothing); needs conversion, not annotation:
  - `base_vars` (22 rows): `controllers/subsystems/overlays.dm` (2), `datums/properties/families/temperature_thresholds.dm`, `game/atom/_atom.dm` (4),
    `game/atom/armor.dm`, `game/atom/atom_defense.dm` (3), `game/atom/atom_type_table.dm`, `game/atoms_movable.dm` (4), `game/objects/items.dm` (2),
    `modules/body/factors.dm`, `modules/catalogue/atoms.dm`, `modules/lighting/lighting_atom.dm`, `modules/mob/living/carbon/carbon_defines.dm`,
    `modules/mob/living/carbon/shock.dm`, `modules/mob/living/default_language.dm`, `modules/mob/living/life/life_om.dm`, `modules/mob/mob_defines.dm` (2);
    `list_init`: `modules/projectiles/targeting/targeting_mob.dm`, `modules/refinery/core/industrial_reagent_grinder.dm`.
  - `sys/dx_review`: `modules/power/apc.dm` (`manual_push`), `modules/mob/living/silicon/robot/robot_ui_module.dm` (2 `output_side_effect`).
  - `lane_ready_global.txt` names `code/modules/unit_tests/unit_test.dm`: a move needs the path updated there (a one-line change in its move commit).

**systemowner (20 left, was 35).** Files defining `/datum/system/X` procs apart from the `SYSTEM_DEF(X)` file: `ATMOSPHERICS/{air_api,rust_pipenets,xgm_compat}.dm`,
`controllers/subsystems/{garbage,job,lighting,ticker,ticker_roundend,ticker_roundstats}_api.dm`, `game/objects/items/devices/radio/radio_api.dm`,
`modules/economy/{cargo_market,service_invoices,supply_agent_api,supply_api}.dm`, `modules/expedition/{api,expedition_debug}.dm`,
`modules/mob/living/silicon/pai/api.dm`, `modules/resleeving/transcore_api.dm`, `modules/skybox_api.dm`, `modules/unit_tests/_test_build_overrides.dm`.
Not moved in this lane: each owner file is itself dirty (oldform or allow), so owner and procs have to move in the same wave as the owner's conversion.

**Base vars left in place (2026-10-31 verb and baseline sweep).** `light_flags` became a sparse slot, `aimed` and `holdingitems` lazy lists; the rest stay, each for a reason:
- `atom_colours` (`game/atom/_atom.dm`): the state serializer saves it as a list var and special-cases it in `pristine_lists()` (`engine/state/serializer.dm`). The serializer has no sparse-slot handling and no test names `atom_colours`, so a move to a slot would drop it from save and restore and nothing would catch it. Needs the serializer to save `sparse_slots` first.
- `identity_type`, `init_hide_identity` (`game/objects/items.dm`): read by `starts = when(nameof(init_hide_identity), nameof(identity_type))` on the item block (`modules/mob/living/silicon/robot/component.dm`). The `starts` form names vars, so the pair needs a per-type declaration form before it can leave the base type.
- `realized_overlays`, `realized_underlays`, `our_overlays` (`controllers/subsystems/overlays.dm`, `game/atom/_atom.dm`): the per-atom overlay realisation cache on the appearance hot path; a slot list per atom with overlays costs more than the vars.
- `shock_stage` (carbon), `life_tick`, `life_set` (`mob/living`): written every life tick of every mob; a slot lookup per tick, and `life_tick` is touched by the life sequence itself.
- `insulation` (`/obj`, `datums/properties/families/temperature_thresholds.dm`): a type default read through `initial()` by a property provider; it needs the property-family provider redesigned, not a trait.
- `default_language`, `faction` (`/mob`), `simulated`, `germ_level`, `armor_spec`, `catalogue_data`, `uses_integrity`, `atom_integrity`, `integrity_failure`, `init_from_table`, `worn_factors`: 55 to 2400 references each, set as type defaults in type bodies, which a slot cannot carry (a type default needs a trait block; none exists for these).
- `move_speed`, `last_move`, `old_x`, `old_y` (`atoms_movable.dm`) and `bodytemperature`: written on every move or life tick; `move_speed` and `bodytemperature` were excluded by instruction.
- The seven `ALLOW(base_vars)` files (`proximity.dm`, `structures.dm`, `floor.dm`, `material_construction.dm`, `living_defines.dm`, `autofire.dm`) and `ALLOW(decl)` in `spore.dm` were reviewed and kept; none is stale.
- `sys/dx_review` `manual_push` in `modules/power/apc.dm` (`push_to_rust()` after the bind) stays: it needs the power domain's refresh redesigned.
