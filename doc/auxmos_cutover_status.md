# auxmos cutover — status

Status of the full-auxmos cutover on branch `claude/charming-chebyshev-b939a5`.
Companion to `doc/auxmos_wiring_plan.md` (the plan) — this is the *current state*.

## Where it stands — COMPLETE

DeepQuarry's LINDA atmospherics now runs entirely on the vendored Rust auxmos
arena, and the atmospherics unit-test suite is **fully green**:

- **Compiles clean** (0 errors) under `-DUNIT_TESTS -DUSE_MAP_SOUTHERN_CROSS`.
- **Boots** without an init crash.
- **All atmos unit tests pass** — last VM run: **222 PASS / 0 FAIL** (baseline before
  the cutover was 227 PASS / 1 FAIL; the gap is closed).
- Gas diffuses through the Rust FDM, reactions fire (23 DM gas reactions dispatched
  on arena accessors), pressure equalises, multi-z vertical sharing works, planetary
  atmospheres drain, combustion/hotspots run, gas thrusters produce thrust,
  `reconcile_air` conserves mass, and gas overlays render as gas spreads.

`/datum/gas_mixture` is an arena handle (no DM `gases` list); `SSair.fire()` drives
`process_turfs_auxtools`→groups→equalize→finish→callbacks; the DM turf engine
(`process_cell`/active-turfs/excited-groups/super_conduct) is deleted.

## Root causes fixed during bring-up (for reference)

- **Turf registration flag**: `update_air_ref(0)` registered turfs with *empty*
  `SimulationFlags` → auxmos FDM skipped every turf. Fixed: register with
  `SIMULATION_ANY` (`dq_linda_turf_air.dm`).
- **`init_gas_reactions` positional-index bug**: `group_counters[reaction.priority_group]`
  used a *number* as a list index → out-of-bounds runtime → `SSair.gas_reactions` null.
  Fixed: stringify the key.
- **`get_gases()` returned a flat list** of gas-type paths; callers that read the value
  (`gases[id]`) got null. Made it an assoc `path -> moles`. Fixed gas visuals, gas
  thruster mass/thrust, `reconcile_air` mass balance, and `share_ratio`
  (`gas_mixture.dm`).
- **Whole station booted in vacuum**: turf air is parsed during mapload (each
  `/turf/open/Initialize` → `create_gas_mixture` → `set_moles`), which runs BEFORE
  `SSair.Initialize` registered the gas roster — so every `set_moles` failed
  ("Invalid gas ID") and all mixtures were empty. Fixed: register the gas roster
  lazily on the first `gas_mixture/New()` (`ensure_auxmos_gas_registry()`), guarded
  to run once (`auxmos_init_bridge.dm`).
- **Runtime-built turfs didn't share gas**: auxmos stores adjacency as DIRECTED graph
  edges; a turf built at runtime (ChangeTurf, a freshly loaded z-level, the unit-test
  room) only pushed its own out-edges, so the reverse edge was missing and gas never
  flowed back. Fixed: `air_update_turf` now pushes adjacency BOTH directions
  (`LINDA_system.dm`). This fixed pressure equalisation, multi-z vertical share, and
  planetary drain.
- **Planetary baseline captured while polluted**: auxmos snapshots a planetary turf's
  baseline mix from its current air at registration. A turf flagged planetary at
  runtime after being polluted snapshotted the pollution. Fixed by registering the
  planetary turf while still clean (mirrors how mapload planetary turfs register).
- **`set_visuals` recomputes from air**: the DM `set_visuals` (called by the Rust
  turf-processing loop) now recomputes overlays from the turf's arena air rather than
  trusting the Rust-passed list, so it's the single source of truth.
- **Gas-recipient tiles didn't refresh visuals**: auxmos' FDM pushes gas INTO a
  neighbour from an active turf's `process_cell` without the neighbour itself being
  active, and the arena's `post_process` pass (which fires the gas-overlay + reaction
  callbacks) only visits ENABLED turfs — so a tile that merely RECEIVED gas never got
  its overlay refreshed. Fixed: `air_update_turf` re-registers (enables) each
  neighbour, not just pushes its adjacency (`LINDA_system.dm`).
- **Callback-drain starvation**: the Rust→DM callback queue (gas overlays + reactions)
  was only drained in the stepped pipeline's finalize step, which starves when the
  turf step pauses on overtime. `SSair.fire()` now drains callbacks unconditionally
  each fire with a floored budget (`SSair.dm`).
- **Panic hazard**: `byondapi_stack_trace` logs deduped (was flooding).

## Hardening done

- **Rust panic-safety (Task 1) — DONE.** Every one of the 57 auxmos FFI binds is now
  wrapped in `catch_unwind` via a new `#[auxmacros::panic_safe]` attribute
  (`verdigris/atmos/crates/auxmacros/src/lib.rs`), applied directly under each
  `#[byondapi::bind(...)]`. A panic inside a bind (a bad DM arg, a missing compiled
  string, an out-of-bounds index, an `unwrap` on None) is now converted to an `Err`
  that byondapi routes to `/proc/byondapi_stack_trace` (logged deduped) instead of
  unwinding across the `extern "C"` boundary and aborting DreamDaemon.

## Known-remaining (not blocking; scoped out)

- **Superconductivity / heat-conduction — ENABLED (ported to byondapi).**
  `verdigris/atmos/src/turfs/superconduct.rs` is fully ported to byondapi 0.6.x and the
  `superconductivity` cargo feature is ON. It runs turf-to-turf, turf-to-space
  (radiation), and turf-to-gas heat sharing on a detached rayon worker; DM fires it via
  a new `SSAIR_SUPERCONDUCTIVITY` step (`SSair.fire()` → `process_turf_heat()`), results
  land through the atmos-callback queue. Turf vars used: `thermal_conductivity`,
  `heat_capacity`, `temperature`, `conductivity_blocked_directions`,
  `should_conduct_to_space()`, `to_be_destroyed`; turf temperature reads route through
  `/turf/proc/return_temperature`. Unit-test boot: 222/222, no init crash, no
  superconductivity runtimes.
  - **BYOND-516 caveat baked into the port:** byondapi 0.4.11's error-fetch path
    (`ByondError::get_last` → `CStr::from_ptr(Byond_LastError())`) hard-crashes DreamDaemon
    whenever a `read_var_id` on the World value fails on BYOND 516. So the port never reads
    world/global vars from Rust: DM pushes `world.maxx`/`maxy` in once at init via
    `auxmos_set_world_dims()`, and the per-tick `cost_superconductivity` profiling writeback
    (which read `SSair` off the global) was dropped.
- The DM `.temperature` mirror is best-effort; correctness-sensitive reads should use
  `air.return_temperature()`.
- **BYOND-516 byondapi crash — FIXED by upgrading byondapi + the BYOND runtime.** Previously
  the unit boot crashed AFTER all 222 passed, during `dq_expedition_generates_site`, inside the
  gas `update_visuals` callback: any `read_var_id` that *failed* hit `Byond_LastError` and
  hard-crashed DreamDaemon. **Root cause:** the Rust atmos library was built with byondapi
  0.4.11 / byondapi-sys 0.11.2, whose newest bindings are BYOND **515-1621** — the *515*
  `CByondValue` struct layout and `Byond_LastError` ABI — but the runtime was BYOND **516**. The
  ABI mismatch corrupted the failure path. (A first pass masked it by vendoring byondapi 0.4.11
  and neutering `Error::get_last_byond_error()`; that shipped green but left us on the wrong ABI.)
  **Proper fix:** upgraded to **byondapi 0.6.x (git, feature `byond-516-1682`)** — the modern 516
  ABI (buffer-based `Byond_LastError`, `DecTempRef`/persistent-off-thread-ref handling) — and
  bumped the pinned BYOND runtime **516.1681 → 516.1682** (`dependencies.sh`, `.tgs.yml`), the
  build that first exports that ABI. Note the version knife-edge: `Byond_LastError` kept its old
  pointer signature through 516.1681 and switched to the buffer form at 516.1682, while
  `DecTempRef` also lands at 1682 — so 1682 is the *first* self-consistent runtime for modern
  byondapi, and the auxmos source needed **zero** changes to compile against it. Boot on
  516.1682 is crash-free (222/222, 0 crashes, 0 undefined symbols). The vendored byondapi and
  the `is_valid_ref` guards were removed. byondapi is pinned to a git rev only because 0.6.x is
  not yet on crates.io — switch to a crates.io release once one lands.

## How to iterate (see memory `ss13-gcp-vm`)

Fast loop (no image rebuild for DM changes): sync worktree → VM, bind-mount
`code/maps/dme` over `dq:full`, `DreamMaker -DCBT -DCIBUILDING -DUNIT_TESTS
-DUSE_MAP_SOUTHERN_CROSS` then `DreamDaemon`, read `~/dq-data/dd.log`
(`grep -c '^PASS '`, `grep FAILURE`). A Rust (`verdigris/`) change or new icons need a
full `docker build`.
