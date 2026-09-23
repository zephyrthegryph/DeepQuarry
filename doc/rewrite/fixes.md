# Fixes and quick wins (track F)

This track covers work that doesn't wait for the new architecture. Each fix here is small and local, and each one lands on its own with a regression test or a before/after benchmark.

Later tracks will replace some of this code, but the bugs still get fixed now: they affect play today, and the regression tests carry over to the new code.

## 1. Correctness bugs

| ID | Where | Problem | Fix | Replaced later by |
|---|---|---|---|---|
| B1 | `verdigris/atmos/src/turfs.rs:1576` `adjacent_tile_id`, used by `turfs/superconduct.rs:185-207` | East and west neighbours are `i ± 1` and north is `i + max_x`, with no bounds check. Heat leaks across the map's east/west edge, and from the top row into the next z-level. | Bounds-check x and y | R2 grid |
| B2 | `/atom/fire_act(air, T, V)` at `code/game/atom/_atom.dm:275` vs `/obj/fire_act(T, V)` at `code/game/objects/obj_defense.dm:2`; hotspots call it with `(T, V)` (`code/ATMOSPHERICS/environmental/LINDA_fire.dm:174-218`) | 33 of the 41 overrides take `(air, T, V)`, so they read volume as temperature: windows, floors, carbons and living mobs among them. Bonfires and lava pass `(null, 1000, 500)`, which gives `/obj` a null temperature. | One signature; convert every override and caller | D1 packets |
| B3 | `/mob/living/carbon/resolve_item_attack` (`carbon_defense.dm:2`) | It throws away the parent's return value and its signature doesn't match, so weapon melee never lands on non-human carbons (aliens, nymphs) | Fix the signature and the return | — |
| B4 | `code/controllers/subsystems/machines.dm`: `machine_wake_reason_counts` (:93, :827, :1150) and `reactive_revisions` (:86-94) | Both tables grow all round. Their keys embed mixture IDs and REFs, and they are only cleared while profiling is on. | Count wake reasons only while profiling; prune revisions that have no subscribers | S2 |
| B5 | `cyborg.dm:171` | Ctrl-shift-click calls `click_ctrl_shift` on the borg itself instead of the target | Pass the target | I1 |
| B6 | `rig.dm:38` and `ventcrawl.dm:100` | `/mob/living/AltClickOn` is defined twice, and the last include wins | Merge them | I1 |
| B7 | `code/datums/wires/wires.dm:28-52` | Non-randomized types share `GLOB.wire_color_directory[holder_type]`, so changing one machine's colours changes them for its whole type | Copy on write | C6 |
| B8 | `wall_icon.dm:15-17`, `material_composites.dm:16-20` | `material_thermal_conductance` is always at least 10 for walls, so the clamp makes every wall 0.25 and material differences have no effect | Fix the scale | M4 |
| B9 | `cold_sink.dm:124-163`, `spaceheater.dm:214-252`, `airconditioner.dm:52-88` | Cooling deletes the heat it removes | Reject the heat to the hot side | H4 |
| B10 | `heat_source.dm:68-94` | Adds 2.5 × power × coolant factor as heat, more energy than it draws | Cap it at the power drawn | H4 |
| B11 | `cryo.dm:212-254` | Mixes in a phantom 50 J/K reservoir at T20C every tick, and `HEAT_CAPACITY_HUMAN` is 100 | Remove the reservoir and use the real heat capacity | H2, H4 |
| B12 | `atmos.dm:32` vs `reactions.dm:45`; `verdigris/atmos/src/gas/constants.rs:60-61` vs DM | Two different phoron ignition temperatures, and Rust's superconduction thresholds differ from DM's | One value for each | H1 (generated constants) |
| B13 | `code/datums/components/species/shadekin/powers/phase_shift.dm:22-103` | Energy is deducted and the sound plays before the final `CanPass` check, so a failed shift still costs energy. The watcher loop also calls `oviewers(7, src)` once per candidate inside `orange(7)`. | Move every check before the energy is spent, and compute the viewer list once | P5 |
| B14 | `verdigris/atmos/src/gas.rs` `equalize_mixture_ids` | Writes without taking the mutation gate, so an update can be lost | Take the gate | R4 |
| B15 | `code/_helpers/radiation.dm:82` and `:45` | The insulation cache expires every second but sources pulse about every 2 s, so it always misses; `GLOB.living_mob_list` is copied on every pulse | Cache by topology revision and iterate without copying | M5 |
| B16 | `fire_stacks.dm:237`, `:224` | `harm_human` passes the number of fire stacks as the exposure temperature, and calls `hotspot_expose` every tick | Pass the real temperature | H3 (object/tile side done: burning is a state and `burn_gas_step()` is the shared gas side; the mob `Life`/body side is H2's) |
| B17 | `damage_organs.dm` (`BURN`) and `combat.dm` (`FIRE`) | The damage type `BURN` and the armour flag `FIRE` are the same string, `"fire"` | Give them distinct values | D1 |
| B18 | `code/game/atom/_atom.dm:604` `get_all_contents_type` | Quadratic, because it uses `Cut(1,2)` in a loop | Iterate by index | C1 |
| B19 | `code/modules/vore/eating/belly_obj.dm:1611-1631` `update_belly_surrounding` | Allocates a new list for every empty belly on every tick, and `process()` runs even for empty bellies | Skip empty bellies | C7 |
| B20 | 62 `take_damage` calls with one argument | No damage type or armour flag | Pass both | D1 |
| B21 | `interface/skin.dmf:1284` | The map element doesn't set `right-click=true`, so right-click probably opens BYOND's verb menu and the secondary click chain never fires. **Confirm in the client first.** | Enable it with I1 | I1 |
| B22 | `code/modules/body/…/emergent.dm:312-324` (body rewrite's code) | The thermal metric hardcodes 310.15 K instead of the species' `body_temperature` | **Report to the body rewrite; don't edit** | — |

## 2. Boot quick wins

| ID | Evidence | Change |
|---|---|---|
| Q1 | Assets take 17.7–24.7 s. One profiled boot spent 51 s in `md5asfile`, 40.5 s of it from `tgui_chunks` registering all 858 `*.chunk.js` files when only 416 appear in `tgui-chunk-manifest.json`. | Register only the chunks in the manifest, and use content hashes computed at build time. A July test found swapping in rust-g's hash was slower, so don't do that. |
| Q2 | `preload_size` parses 201 templates just to read their bounds: 2.5 s (`map_template.dm:32`) | Cache template bounds at build time |
| Q3 | Holomaps draw one `DrawBox` per pixel (`generate_holomap.dm:63-95`): 1.1–3.7 s | Generate them with `rustg_dmi_create_png` |
| Q4 | `update_character_previews` blocks for about 351 ms (`getFlatIcon` for 4 directions, `preferences.dm:222`) | Use async iconforge (`rustg_iconforge_generate_async`) |

## 3. Runtime quick wins

| ID | Evidence | Change |
|---|---|---|
| Q5 | `sound_loop` took 62 s, plus 1.9M timer inserts (28 s), in a 3-hour round with one player | Loop only while a listener is in range, using the mob chunk keys (the reactor later replaces those keys) |
| Q6 | `playsound` copies `player_list` and builds a `sound()` on every call (`sound.dm:14-16`); EMPs call `playsound` once per mob (`empulse.dm:28`) | Iterate listeners in range and build the sound once |
| Q7 | `set_MC_tab` took 59 s and `sortTim` 26.5 s, mostly from `performance_window` (`master.dm:902`) | Use a rolling histogram, so percentiles don't need a sort |
| Q8 | Logging does two `fexists` per entry (`log_entry.dm:98`); there are about 20,000 runtimes a round (`log_runtime` 15.7 s) | Cache whether the log file exists, and fix the top runtime sources (see §6) |
| Q9 | Bots ran 5,713 JPS searches and only 9 unwound a path. Failed searches aren't cached. Combat AI A* costs 19 ms a search. | Cache failures, keyed by `SSai.navigation_revision` |
| Q10 | SStimer builds a 9-slot debug list of interpolated strings on every insert, even without `TIMER_DEBUG` (`timer.dm:537-549`) | Build it only under `TIMER_DEBUG` |
| Q11 | `processing_machines.Copy()` runs every pass, and hibernation does linear `Remove()` calls on `processing_machines` and `current_run` | Remove by index (S2 replaces all of this) |
| Q12 | Every mob step builds chunk-key strings and calls `get_turf` 4 times (`atoms_movable.dm:270`) | Numeric keys, built only when something is subscribed |
| Q13 | `makepowernets()` runs after every explosion. Cable edits publish to every sleeping APC, and `worklist \|= C.get_connections()` is quadratic (`power.dm:241`). | Batch explosion rebuilds, publish per affected net, and use a set for the worklist (M3 replaces this) |
| Q14 | `wake_all_automatic_shutoff_valves()` wakes every valve on any leak change (`shutoff.dm:3-11`) | Wake only the valves on the affected network |

## 4. Low-risk memory

| ID | Where | Change | Saves (estimated) |
|---|---|---|---|
| MEM1 | `material_construction.dm:340-345`: every pipe, cable and machine copies two lists | Share one pair per material profile and amount, and copy on write. `ensure_pump_materials` (`material_equipment.dm:4`) mutates them. | ~58k lists |
| MEM2 | `wires.dm:28-52`: `cut_wires`, `colors` and `assemblies` created eagerly on about 2,500 holders | Lazy lists, and don't build a `colors` list that is thrown away | ~7k lists |
| MEM3 | `air_alarm.dm:26-35, 105-106, 179-186`: 8 eager lists plus a nested threshold table, × 463 alarms | A static default threshold table copied on edit; lazy lists for the rest | ~6.5k lists |
| MEM4 | `firedoor.dm:37, 398-408`: an eager `users_to_open` list, plus hibernation snapshot lists, × 2,070 | Lazy, and reuse the snapshot storage | 4–6k lists |
| MEM5 | `vent_scrubber.dm:23`: `scrubbing_gas` on every scrubber | A static default, copied when changed | ~600 lists |
| MEM6 | `unary_base.dm:29`, `binary_atmos_base.dm:15-16`: eager `air_contents`, later replaced by the network's air | Create on demand | ~1.4k datums |
| MEM7 | `camera.dm:15`: a network list per camera | Share lists between cameras with the same network set | 340 lists |
| MEM8 | `hologram.dm:43` `masters`; `vore/eating/mob.dm:11` `vore_organs` on every mob; `smes.dm:55` `terminals` | Lazy | small |
| MEM9 | Q10's per-timer debug list | (Q10) | one list per timer |

## 5. Dead code

| ID | What | Notes |
|---|---|---|
| DEAD1 | Verdigris: `turfs/monstermos.rs` (894 lines), `turfs/putnamos.rs` (241), `reaction/citadel.rs` (404), `yogs.rs`, the `fastmos` feature, the `katmos` references in `UPSTREAM.md`, and the unused generated `atmos/bindings.dm` | None of these are compiled or included |
| DEAD2 | The DM room solver, `generated_station_room_solver.dm` (1,241 lines) | `synthesize_rooms()` has no callers; Rust `content.rs` does this now |
| DEAD3 | `temperature_expose`, `atmos_expose`, `should_atmos_process` and `burn_turf` (`LINDA_turf_tile.dm:186-228`); `adjacent_fire_act` (`turf.dm:310`, `walls.dm:192-195`); Rust writes of `to_be_destroyed`; the Rust `temperature_share` binds, which DM never calls; the broken `THERMAL_ENERGY` macro; the unused DM superconduction, space and window constants | None of these have callers. H3 builds their replacements. |
| DEAD4 | `audit_reactive_sleepers` and `audit_sleeping_gas_subscribers` | Zero callers. Either wire them into tests or delete them; S2 replaces both. |
| DEAD5 | Signals never sent: `COMSIG_TURF_CHANGE` (listened for but never sent), the storage signals, the screentip signals, and the four machinery signals | L4 decides for each one: wire it up (the machinery signals, in M3) or delete it |

## 6. Hard deletes and runtimes

- **Hard deletes.** The profiled round had 428 hard deletes at about 140 ms each, and every one is a visible hitch.
  - Read SSgarbage's hard-delete log (types and reference holders) and fix the top holders.
  - Global lists that keep references are a common cause, and L3's registries remove that class.
  - Add a hard-delete count to the idle and generation benchmark metrics.
- **Runtimes.** There are about 20,000 per round. Group `runtime.log` by source line and fix the top 20. Every runtime also costs a log write (Q8).
