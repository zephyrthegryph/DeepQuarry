# Change sweep 2 (rewrite/change-sweep2)

Takes over the files the first change sweep skipped because Codex lanes touched them, and deletes what that leaves unused: the machine
and grid change channels, `changed()`, `TRACKED_BRIDGED`, the declared caches and the channel wakes of kernel sequences.

## What a reader of the old code needs to know

| Old form | Now |
|---|---|
| `TRACKED_BRIDGED(T, v, CHANGE_MACHINE_*)` (95 sites) | `TRACKED(T, v)`. Nothing waits on a machine channel: the machine pipeline (`machine_step()`, `MACHINE_WAKE()`) was deleted in F7, and no type declares a `scheduled_behaviour`, `work_stage` or `work_pipeline`. |
| `/datum/scheduler_field_definition/...` rows with a channel (machinery_fields.dm and six machines) | deleted. `OM_DERIVE_FIELD` (derived fields) is the only form left of that table. |
| `changed(E)`, `changed(E, CHANNEL, var)` | deleted. A write publishes through its setter; a key that is not one var is `PUBLISH_CHANGE(E, key)`. The engine's own mark is `state_changed(E)` and is banned outside the engine, the capability framework, `machinery_fields.dm`, tests and benchmarks (`banned_outside` in `lint_scopes.toml`). |
| `condition_announce(channel)` | `condition_announce()`: publishes `MACHINE_KEY_STAT` and re-derives every output of the machine. A draw reads a condition through an accessor (`power_lost()`, `operable()`, `broken_now()`) that no derived read binds to the key yet, so the full mark stays (it was `changed(src, channel)`). |
| the dispatcher's `changed(target)` after every handler | `refresh_dispatched(target)`: the same re-derive, without the `CHANGE_EXPLICIT` wake of every sequence on the target. |
| VV edit of a var with no setter | `refresh_dispatched(src)`. |
| `timed_set()` on a var with no registered setter | refused (`CRASH`). Nothing in production called it that way. |
| `CACHE_ON_CHANGE` / `declared_cache_vars()` (asset URL mappings, overmap skybox, AI laws, world model, expedition floors, generated-station plan, POI queue) | the asset mappings and the skybox images are shared caches (`asset_url_mappings`, `overmap_skybox_images`, `SC_EXPLICIT`, dropped by the producer); the others were live state that an unrelated mark used to wipe, and are plain state now. |
| `wake_all` / numeric `reads` / `chan_mask` of a kernel sequence, `LIFE_WAKE_ALL` | gone. A step wakes on the keys it reads and the sequence's `wake_keys`; `seq_wake()` wakes one entity. |
| wires: `changed(owner, 0, WIRES_KEY)` | `PUBLISH_CHANGE(owner, WIRES_KEY)`; the airlock's wire notice hooks that only re-marked the door are gone (its draw follows the stats the wires hold). |
| turbolift buttons and panel: `lift` was a plain `tmp` var and the modes published nothing | `lift` is `ref_one()` (set with `rel_set()` where the lift is built, no `param`), `fire_mode` and `priority_mode` are `TRACKED`, the hand `update_ext_panel_icons()` marks are gone. |
| omni device overlays `overlays_on/off/error` | `TRACKED` lists written through the generated `set_x_at()`; the `ALLOW(derived_reads)` and the hand mark are gone. |
| airlock sensor `alert`, field generator `power`, reconstitutor `nanomass_reserve` / `processing_revive` | `TRACKED`, written through setters; their hand marks are gone. |
| the init ratchet counting `set_x(v)` as a new site where `x = v` was baselined | the baseline compares an `init_lines` site by the job it does (`x = v` and `set_x(v)` are the same site, `baseline.rs` `canon_text`). Converting a write to its setter, which the `tracked` lint requires, no longer adds a site. A raw write in `Initialize()` stays refused: after `..()` the stat layer is already set up and would not recompute. |

## Left, and why

* `CHANGE_EXPLICIT`, `CHANGE_RELATED`, `CHANGE_RELATION_ADDED/REMOVED`, `state_changed(E, channel, var)`, `refresh_bits` and
  `on_state_changed(bits)` stay. They are the engine's own: the legacy scheduler layer (`code/engine/time/{pipelines,records,scheduler}.dm`,
  `code/engine/state/{field_tables,derived_values}.dm`, `code/engine/refs/edges.dm`, the behaviour registry) and the Rust change delivery
  (`entity_raise_change()`, `NATIVE_SRC_*`) still carry channel masks. Nothing in game code declares a behaviour, stage or pipeline any more, so
  that layer is dead weight with unit tests (`kernel_stages`, `kernel_work`, `dq_state_batch_tests`, `dq_om_periodic_tests`); deleting it is the
  OM retirement, not a sweep. The 150 `refresh_bits: CHANGE_EXPLICIT -> 0` rows of the hit pins record it.
* The hit, conversion and machinery pins and `dx_menu_order`, `dx_deps_drift_names_read`, `dx_deps_output_writes_state` fail on origin/master
  (785d51e138) before this lane: checked in a clean worktree. They are not blessed here.
