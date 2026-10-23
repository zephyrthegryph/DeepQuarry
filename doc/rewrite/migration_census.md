# Migration census (2026-10-22)

An honest count of what is left between master and the design in `final_api.html`. Sources: `bash tools/ci/legacy_form_counts.sh`,
the non-empty `tools/ci/*_baseline.txt` files, and a file scan of `code/` (method at the end). Numbers are for the tree at this commit;
`init` is 557 here (566 on `origin/master` before the `system_boundary` lane, which converted the paintings `Initialize()` and shrank
`init` by 9). Effort is in **waves**: one lane converting roughly 20-40 files (about a day of agent work plus its review and gates).
These are estimates from site and file counts, not measurements.

## Verdict

- Every hard-banned legacy form is at zero, and `legacy_form_counts.sh` reports no non-zero row (its `CHANGE_` hits were an overmap macro and a doc-comment placeholder, now renamed). The doc §17
  replacements for the banned forms have landed and their callers are converted; what is left is **sites of forms whose replacement has
  landed but whose callers are not all converted** (init, base vars, stored refs, native ref writes, a slice of ref text).
- `system_boundary` is now empty (5 -> 0): see the next section.
- Of the live ratchets, five are real migration (init, base_vars, stored_refs, native_ref_write, decl), `ref_text stored` is migration
  (relations D9), two are mostly code quality (`untyped`, `ref_text ref_macro`), and `op_order` and `escape_hatches` are small keeps.
- Moving files into the new tree (§22) is gated by files being fully clean, not by ratchets alone: **4,723** of 5,488 old non-test `.dm`
  files have no ratchet site at all; 3,880 survive a stricter text screen.

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
| `init` | 557 (542 `init_lines` + 15 `world_reads`) | 100 | Each imperative line in an `Initialize()` override, and `GLOB.`/`range(`/`START_PROCESSING` reads at init | M (§6, §17) | `starts =`, `rolls()`, `param()`, `on_holder_init(A)`, `after_init()`, `setup(PROC_REF(x))`, `membership()` | yes | About 6 waves. About 5.6 lines per file; contents, timers and registration are mechanical. Per-instance state no form names stays under `ALLOW(init/CODE)`. |
| `ref_text` | 542 = 400 `ref_macro` + 142 `stored` | 226 | `ref_macro`: a `\ref[...]` text in code (mostly Topic hrefs). `stored`: a `REF()` result kept in a var, list or key | `stored`: M (relations D9). `ref_macro`: Q | `ref_token()` in data, `ref_one(weak = TRUE)` in content; for hrefs `interface()` + `ui_act` | yes | `stored`: 2 waves. `ref_macro`: do not convert by hand; it falls as each Topic window becomes `interface()`/`op(ui_act)`. |
| `base_vars` | 526 = 518 `base_var` + 8 `list_init` | 144 | A var declared on a base type (`/atom`, `/obj`, `/mob`, ...); an instance `= list()` | M (§4/§7, base_vars proposal) | Trait block, profile record, HUD datum, owning domain, `TRACKED`/`STAT`, `sparse(T, x)`, cooldown table, relation | yes | Largest and most design-bound: 8-10 waves. Each var needs a home decision; `analyze base-vars-dead` finds the free ones (delete) first. |
| `untyped` | 508 = 451 `call` + 57 `typed` | 316 | An untyped `var/x` that a proc assigns an atom/datum (or an uncheckable call result) | Q (closes a hole in `stored_refs`, relations D8) | Declare the type, then a relation (`ref_one`/`owns_one`/`weak = TRUE`) or a non-reference type | yes | About 6 waves, mostly mechanical typing; the 451 `call` rows need a look at what the call returns. Many vanish when the owning file converts. |
| `stored_refs` | 107 = 61 `list` + 46 `var` | 76 | A typed atom/datum var, or a list filled with atoms/datums, that no relation declares | M (§6 "Storing references") | `ref_one`/`ref_many`/`owns_*`/`links()`/`slot()` | yes | 3-4 waves; each is a lifecycle decision (who clears it), so slower per file. |
| `native_ref_write` | 104 | 52 | Raw `+=`/`-=`/`.Add()` on `vis_contents`, `client.images`, `client.screen` | M (relations D11) | `vis_add`/`vis_remove`, `client_screen_add`/`_remove`, `client_images_add`/`_remove` (`code/engine/present/native_ends.dm`) | yes | 2 waves, near-mechanical; concentrated in `_onclick/hud`, pAI HUD, smite, GPS. Then it becomes a ban. |
| `decl` | 4 (3 `destroy_drop`, 1 `init_new_child`) | 4 | Work in `Initialize`/`on_destroy` that a lifecycle declaration does | M (declarative lifecycle) | `starts =`/`owns_one`; slot spill / `on_destroy` forms | yes | Under one lane. |
| `escape_hatches` | 123 ceiling units (`init_allow` 36, `usr_allow` 5, `usr_content` 82) | ceilings only | Kept `ALLOW(init/...)` overrides, kept `usr` sites, every `usr` outside engine and verbs | Q | Per-instance init stays where no form fits; pass the actor in instead of `usr` | partly (`init_allow` is a justified-keep list, not all debt) | `usr_content` 82: about 2 waves. `init_allow` falls with `init`. `usr_allow` 5: trivial. |
| `op_order` | 1 ceiling = 15 `relative_priority` | ceilings only | Hand-written `priority(above(...))`/`below(...)` | Q | `click_order()` on the bundle that owns both ops | yes | One lane. |
| `system_boundary` | 0 | 0 | See above | M (§2) | `api.dm` procs | yes | Done. |

Open forms with no ratchet (AGENTS.md §3b): none. No `flow_ask` question remains (the macro is deleted and banned); the `prompt_flow()` hits in the
old tree are the kept DB re-run machinery (`code/datums/prompts/reruns.dm`, DB bans, polls, `log_client_to_db`, TGS commands), not prompts. `CHANGE_` outside the
engine is at zero.

Total of the baseline-row ratchets: **2,348 rows** (557 + 542 + 526 + 508 + 107 + 104 + 4)
plus 123 escape-hatch ceiling units. The wave estimates above sum to about 30-35 waves, dominated by `base_vars`, `init`, `untyped` and
`ref_text`. The rows overlap by file (a wave converting a file clears its rows in several ratchets at once), so the true total is lower than
the sum; I have not measured by how much.

## Files that could move now (§22, pure `git mv`)

| Population | `.dm` files |
|---|---|
| All `.dm` under `code/` | 7,070 |
| Already in the new tree (`engine`, `library`, `domains`, `content`, `world`, `defines`, `_generated`) | 326 |
| Old directories, all | 6,744 |
| ... of which tests and benchmarks (`modules/unit_tests`, `tests`, `modules/benchmarks`) | 1,256 |
| ... **old non-test files** | **5,488** |
| ... with at least one baseline site (init, ref_text, base_vars, untyped, stored_refs, native_ref_write, decl) | 748 |
| ... with only a text-visible keep (`ALLOW(init/usr/decl)`, `priority(above/below)`, `CHANGE_*`, `flow_ask`/`prompt_flow`) | 17 |
| ... **no ratchet site at all** | **4,723** |
| ... of those, with none of `Destroy()`, `spawn`, `sleep`, `do_after`, `INVOKE_ASYNC`, `Initialize`, `LateInitialize`, `Topic`, a `/New()` override or `/verb/`, and not under `__defines/` | **3,880** |

By top directory (non-test files, ratchet-clean of total): `modules` 2,905 of 3,380; `game` 1,011 of 1,194; `datums` 262 of 307;
`controllers` 72 of 90; `_helpers` 66 of 72; `ATMOSPHERICS` 44 of 56; `_onclick` 28 of 45; `_global_vars` 19 of 24; `__defines` 295 of 297
(these belong in `code/defines/` by §22). Largest clean `modules` folders: `mob` 655, `clothing` 193, `client` 134, `medical` 114,
`projectiles` 105, `admin` 100, `research` 93, `power` 63.

How to read this:

- **4,723 is an upper bound; 3,880 is the number to plan with.** "Clean" means no ratchet row. The tree has other old shapes no ratchet
  counts (a `Destroy()`/`spawn`/`sleep` use, a `Topic()` window, a `New()` override, a raw `/verb/`). The second figure drops files with those;
  it is still not a proof of "zero old forms".
- The rule is "move when fully migrated, in a pure `git mv` commit". Most files hold several types, and §22 wants one type per file under
  `content/<domain>/`, so a move is pure only when the whole file maps to one destination. Mapping files to domains (`body`, `damage`, `atmos`,
  `power`, `life`, `ai`, `verdigris`, else `content/<domain>`) is the real cost, not the `git mv`; expect to batch by clean folder
  (`clothing`, `reagents`, `hydroponics`) and keep `deepquarry.dme` include order (§2).
- 40 baseline rows in 26 files sit under paths already in the new tree (engine tables exempt by path, `domains/atmos`); they are not in the
  old-directory counts.

## Method

- Baseline rows read from `tools/ci/*_baseline.txt` (the file is the second tab column; `escape_hatches` and `op_order` have ceilings only).
- Text screens over `code/**/*.dm` outside the new-tree directories: `ALLOW\((init|usr|decl)`, `priority\((above|below)\(`, `\bCHANGE_`,
  `\b(flow_ask|prompt_flow)\b`; strict screen: `/Destroy(`, `spawn(`, `sleep(`, `INVOKE_ASYNC`, `do_after(`, `/Initialize(`,
  `LateInitialize`, `INITIALIZE_HINT_LATELOAD`, `/Topic(`, `^/type/New(`, `/verb/`.
- Not counted: the `check_grep.sh` ceilings (fire_act, ex_act, bumped, attack_generic, transform tails), which have no per-file list, and
  `maps/**`.
- To refresh: re-run `bash tools/ci/legacy_form_counts.sh` and count the non-comment rows of each baseline.
