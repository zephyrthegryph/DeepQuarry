# auxmos cutover — status & remaining punch-list

Status as of the full-auxmos cutover work (branch `claude/charming-chebyshev-b939a5`).
Companion to `doc/auxmos_wiring_plan.md` (the plan) — this is the *current state*.

## Where it stands

**The cutover is functionally working.** DeepQuarry's LINDA atmospherics now runs
on the vendored Rust auxmos arena:

- **Compiles clean** (0 errors) under `-DUNIT_TESTS -DUSE_MAP_SOUTHERN_CROSS`.
- **Boots** without an init crash.
- **Gas diffuses through the Rust FDM** — `dq_real_spread_via_ssair_fire` (the
  production-bug acceptance test: plasma spreads A→B under real `SSair.fire()`)
  **PASSES**.
- **Reactions fire** (23 DM gas reactions active; dispatched by
  `/datum/gas_mixture/react()` on arena accessors).
- Latest VM run: **205 PASS / 23 FAIL**, 1 crash (see below). Baseline before the
  cutover was 227 PASS / 1 FAIL, so the remaining gap is the punch-list here.

`/datum/gas_mixture` is an arena handle (no DM `gases` list); `SSair.fire()` drives
`process_turfs_auxtools`→groups→equalize→finish→callbacks; the DM turf engine
(`process_cell`/active-turfs/excited-groups/super_conduct) is deleted.

## Key fixes made during bring-up (root causes, for reference)

- **Turf registration flag**: `update_air_ref(0)` registered turfs with *empty*
  `SimulationFlags` → auxmos FDM skipped every turf (no gas movement). Fixed:
  register with `SIMULATION_ANY` (`dq_linda_turf_air.dm`).
- **Gas identity**: register gases by type-path TEXT; DM wrappers pass `"[gas_type]"`;
  `get_gases()` converts Rust's path-text ids back to type paths.
- **Reaction dispatch**: reactions run in DM (`react()` dispatcher), auxmos reaction
  parser skipped (its `iter()` panicked on our list). Gas registration moved BEFORE
  `init_gas_reactions()`.
- **`init_gas_reactions` positional-index bug**: `group_counters[reaction.priority_group]`
  used a *number* as a list index → out-of-bounds runtime → aborted the proc →
  `SSair.gas_reactions` null → every reaction dead. Fixed: stringify the key.
- **Panic hazard**: `byondapi_stack_trace` now logs deduped (was flooding).

## Remaining punch-list (diagnosed)

1. **Gas visuals (4 tests)** — `no atmos_overlay`, `gas plasma above visible
   threshold produced NO overlay`, `vis_contents didn't grow`,
   `update_visuals left atmos_overlay_types null`.
   Cause: Rust `update_visuals` reads `GLOB.gas_data.overlays[gas_id][vis_factor]`;
   we stubbed `overlays` to an empty list to stop a per-turf error flood, so no
   overlays are produced. Fix: populate `GLOB.gas_data.overlays` in
   `/datum/xgm_gas_data/New()` in the shape Rust indexes — keyed by the registered
   gas STRING id (`"[gas_type]"`) → per visibility-factor → the overlay appearance,
   sourced from `GLOB.meta_gas_info[path][META_GAS_OVERLAY]` (built by
   `generate_gas_overlays`). Match `visibility_step`/`gas_visibility` semantics in
   `verdigris/atmos/src/turfs.rs` (~line 528) and `gas/mixture.rs`.

2. **Expedition runtime-z crash (1, truncates the suite tail)** — Rust panic in
   `finish_turf_processing_auxtools` (`dq_linda_turf_air.dm:44`) during
   `dq_expedition_generates_site`. Expedition loads z-levels at runtime
   (`expedition_controller.dm`), and a turf-processing callback panics on the new
   layer — most likely a turf whose air/adjacency isn't fully registered before
   processing touches it (register-before-adjacency ordering, or a callback hitting
   an unregistered turf). This crash ends the run, so failures *after* it aren't
   counted — fixing it will surface any further tests. Investigate the expedition
   z-load path's `update_air_ref`/`__update_auxtools_turf_adjacency_info` ordering
   and whether `SSair.build_multiz_atmos_levels()` is re-run before processing.

3. **Gas-movement edge cases (~7)** — `pressure didn't drop in walled pair`,
   `multi-z spread failed`, `planetary share didn't drain`, `plasma did not
   equilibrate` (dq_atmos_tests.dm:1166), `self O2 wrong` (:1744), `after
   process_cell on A` (:778 — this test still references the deleted `process_cell`
   path in its setup), `reconcile_air lost mass` (×2, pipe network `reconcile_air`).
   `dq_real_spread` passing proves the core FDM works, so these are per-test:
   some assert via setups that used deleted DM internals (rewrite to the production
   path), some are genuine (multi-z vertical share and planetary share need
   verifying against the auxmos UP/DOWN + `ExposedTo` paths). `reconcile_air` (pipe
   network mass balance) was rewritten off `gases[]` — recheck the arithmetic.

4. **Gas thruster (2)** — `calculate_thrust returned 0`, `powered thruster zero
   thrust`. `gas_thruster.get_mass`/thrust reads gas moles/mass; verify it uses the
   arena accessors (and `GLOB.gas_data.molar_mass`).

5. **vore_tests (4)** — `Failed to create test mobs` / `No valid turf available`.
   A regression from the atmos changes (these passed at baseline). Likely the test's
   turf-finding sees turfs in an unexpected state post-cutover. Confirm whether it's
   collateral (turf/air state) or ordering.

6. **Deferred: panic-safety Rust rebuild (Task 1)** — auxmos binds are NOT
   `catch_unwind`-wrapped, so any missing string/callback is an instant crash rather
   than a recoverable DM runtime (this is why bring-up hit hard crashes instead of
   errors). Wrapping the binds (a `panic_safe_bind` macro in `crates/auxmacros`,
   then a rebuild) would make the whole subsystem far more robust — and is needed
   before production. Also unwired: superconductivity/heat-conduction (DM engine
   deleted, Rust side not hooked), and the temperature mirror is best-effort
   (correctness-sensitive reads should use `return_temperature()`).

## How to iterate (see memory `ss13-gcp-vm`)

Fast loop (no image rebuild for DM changes): sync worktree → VM, bind-mount
`code/maps/dme` over `dq:full`, `DreamMaker -DCBT -DCIBUILDING -DUNIT_TESTS
-DUSE_MAP_SOUTHERN_CROSS` then `DreamDaemon`, read `~/dq-data/dd.log`
(`grep -c '^PASS '`, `dq_real_spread`, `AUXMOS_STACK_TRACE` for deduped Rust
errors). A Rust (`verdigris/`) change or new icons need a full `docker build`.
