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
