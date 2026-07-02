# Wiring auxmos: the full plan of record

This supersedes the "auxmos backend (not wired)" section of
`code/ATMOSPHERICS/README.md` and the aspirational Phase 3–5 notes in
`doc/atmos_migration.md`. It is grounded in the **actual FFI contract** of the
vendored auxmos (`verdigris/atmos/`) and the **actual current DM surface**, both
audited 2026-07-01.

**Decision (locked with the maintainer):**

- **Scope = full auxmos.** Gas mixtures *and* turf processing move to Rust. This
  replaces `code/ATMOSPHERICS/environmental/LINDA_system.dm` +
  `LINDA_turf_tile.dm` turf loops and the `active_turfs`/excited-group machinery
  in `SSair.dm`.
- **Reactions stay in DM.** auxmos's `react()` bind dispatches back to the DM
  `/datum/gas_reaction` roster; `reaction_hooks` stays disabled. `reactions.dm`
  is rewritten off `gases[]` and onto arena accessors.

## 0. Environment / verification constraint (read first)

The dev box this was authored on is arm64 macOS with **no BYOND toolchain, no
SpacemanDMM binary, and no 32-bit cross-linker** — so *none* of this can be
compiled or booted here. auxmos is `#[cfg(target_arch="x86")]` 32-bit-only.

Therefore every chunk below names its **verification owner**: the maintainer's
local BYOND build (`bin/build.cmd`, `bin/test.cmd`) and/or CI
(`run_integration_tests.yml`, which already builds verdigris from source and
boots the unit-test round). Treat any diff produced from the dev box as
**unverified until built + booted**.

## 1. The cutover is (mostly) atomic — plan accordingly

There is no "half-wired" state that both compiles and runs. Concretely:

- `auxmos_bindings.dm` and `gas_mixture.dm` **cannot coexist** — they define the
  same `/datum/gas_mixture` procs (duplicate-definition compile error). The
  moment you fold in the call_ext routes, the DM bodies must be gone.
- Once mixtures live in the Rust arena, any consumer still reading the DM
  `gases[]` list sees **stale/empty** data (silent gas corruption, not a crash).

So chunks 2–6 land as **one PR (or a tight, non-bootable-in-between series)**.
Only chunk 1 (panic safety) and chunk 7 (verification harness) are independently
landable. Budget this as a single focused cutover, not incremental perf wins.

## 2. Before/after data model

**Before (today, live):** `/datum/gas_mixture` owns a DM assoc list
`gases[gas_id] = list(MOLES, ARCHIVE, GAS_META)` (`gas_mixture.dm:22-47`). All
math iterates it in DM. Turf air is `/turf/open/var/datum/gas_mixture/air`
(`LINDA_turf_tile.dm:42`); `SSair` walks `active_turfs` calling
`process_cell()`.

**After:** `/datum/gas_mixture` is a **handle** — one var,
`_extools_pointer_gasmixture` (the arena index). Gas data lives in Rust
(`GasArena::GAS_MIXTURES: Vec<RwLock<Mixture>>`, `gas.rs:24`). Turf air, turf
adjacency graph, FDM sharing, excited groups, katmos equalize, and
superconduction all live in Rust; `SSair` becomes a thin driver that calls the
turf FFI each tick and drains callbacks.

## 3. FFI contract (audited — this is what Rust expects from DM)

### Gas mixture lifecycle
- `New()` must call `__gasmixture_register()` → allocates an arena slot and sets
  `_extools_pointer_gasmixture` (`lib.rs:42`, `GasArena::register_mix`).
- `Del()`/`Destroy()` must call `__gasmixture_unregister()` → frees the slot
  (`lib.rs:49`). **Rule 4:** every handle released on teardown; CI asserts
  `get_amt_gas_mixes() == 0` after the round.
- ~40 math procs become the call_ext routes already generated in
  `auxmos_bindings.dm` (total_moles, heat_capacity, return_pressure, merge,
  __remove/__remove_ratio, transfer_to, react, get/set/adjust_moles, compare,
  temperature_share, scrub_into, get_by_flag, parse_gas_string, …).

### Gas registry / init — `auxtools_atmos_init(gas_data)` (`gas/types.rs:277`)
Reads **`gas_data.datums`** = list of `/datum/gas` singletons. Per gas it reads:
`id, name, flags, specific_heat, fusion_power, moles_visible,
fire_temperature XOR oxidation_temperature, fire_burn_rate XOR oxidation_rate,
fire_products (list gas_id→moles | null), enthalpy, fire_radiation_released`.
Then reads `SSair.gas_reactions` and **panics on duplicate reaction priority**
(`gas/types.rs:306`).

> DeepQuarry gap: `GLOB.gas_data` is a `/datum/xgm_gas_data` of parallel
> string-keyed lists with **no `datums` var**, and our `/datum/gas` singletons
> (`gasmixtures/gas_types.dm`) must be confirmed to carry every field above.
> Chunk 2 builds the adapter and de-dups reaction priorities.

### Turf processing — the DM driver must call, each tick, in order:
1. `process_turfs_auxtools(src, remaining_ms)` (`turfs/processing.rs:22`) —
   reads `SSair.share_max_steps`, `equalize_enabled`, `planet_share_ratio`.
2. `process_excited_groups_auxtools(src, remaining_ms)` (`turfs/groups.rs:20`) —
   reads `SSair.excited_group_pressure_goal`.
3. `process_turf_equalize_auxtools(src, remaining_ms)` (`turfs/katmos.rs:745`,
   needs `katmos`) — reads `SSair.equalize_hard_turf_limit`.
4. `finish_turf_processing_auxtools(remaining_ms)` (`processing.rs:17`) — drains
   the callback queue; returns "overtimed" bool.
   `process_atmos_callbacks(remaining_ms)` (`lib.rs:36`) also drains.
- `thread_running()` (`processing.rs:11`) — true while a worker holds the lock.
- **Callbacks call back into DM** on the main thread:
  `turf.consider_pressure_difference(enemy, diff)`, `air.react(turf)`,
  `turf.update_visuals()`. These DM procs must exist with matching signatures.

### Turf registration / adjacency
- `update_air_ref(flag)` (`turfs.rs:419`) reads `turf.blocks_air`,
  `turf.air._extools_pointer_gasmixture`, `turf.planetary_atmos`,
  `turf.initial_gas_mix`. `flag >= 0` registers/updates; `flag < 0` removes.
  (Turf vars `blocks_air`/`planetary_atmos`/`initial_gas_mix` already exist —
  `LINDA_turf_tile.dm:28,47,62`.)
- `__update_auxtools_turf_adjacency_info()` (`turfs.rs:503`) reads
  `turf.atmos_adjacent_turfs` (assoc `neighbor_turf → AdjacentFlags`). auxmos
  derives edge direction (incl. **UP/DOWN**) from turf coords —
  `Directions::ALL_CARDINALS_MULTIZ` (`turfs.rs:37`). **Multi-z works if the DM
  adjacency builder lists vertical neighbors** — which
  `init_immediate_calculate_adjacent_turfs` already does via
  `SSmapping.multiz_levels` (`LINDA_system.dm:63`). Keep that builder; drop the
  in-DM sharing.

## 4. Panic safety (chunk 1 — CONFIRMED REQUIRED)

The byondapi 0.4.11 `#[byondapi::bind]` macro (audited) wraps the body in a
`match` that converts `Err` → `byondapi_stack_trace`, but does **NOT**
`catch_unwind`. The FFI fn is `extern "C-unwind"`, so a `panic!` (e.g.
`with_all_mixtures`' `.unwrap()` on the arena `OnceLock`, or `hook_init`'s
duplicate-priority `panic!`) unwinds into BYOND's C frames and crashes
DreamDaemon. The migration doc's "believed panic-safe" note is **false**.

Fix: wrap every auxmos bind body so panics become `Err`. Note the crate
boundary — `verdigris`'s `panic_safe!` (`panic.rs:47`) **can't** be used by
auxmos (verdigris depends on auxmos, not the reverse) and it returns
`meowtonin::ByondError` while auxmos binds return `byondapi`/`eyre::Result`. So
the wrapper's home is auxmos's own `crates/auxmacros` (already a workspace
member). Preferred (lowest churn, keeps auxmos re-vendorable): add a
`#[panic_safe_bind(...)]` proc-macro in `auxmacros` that emits a `catch_unwind`
shim and delegates to `#[byondapi::bind]`, then `sed` every
`#[byondapi::bind(` → `#[auxmacros::panic_safe_bind(` across `verdigris/atmos/src`.
Fallback: hand-wrap each body in `eyre`-returning `catch_unwind`. Either way it's
~112 entry points; add a unit test that a panicking bind returns `Err` (surfaces
as a DM runtime) instead of aborting DreamDaemon.

## 5. Feature flags

`verdigris/verdigris/Cargo.toml:25` currently enables
`turf_processing, katmos, katmos_slow_decompression`. **Add `superconductivity`**
— our `LINDA_turf_tile.dm` super_conduct/consider_superconductivity moves to
Rust and `update_air_ref`/`hook_infos` call the superconduct hooks
(`turfs/superconduct.rs`). Leave `reaction_hooks` off (reactions in DM).

## 6. Chunked build order

| # | Chunk | Files | Landable alone? | Verify |
|---|---|---|---|---|
| 1 | Panic-safe all binds + `superconductivity` feature | `verdigris/atmos/src/*`, `verdigris/verdigris/src/panic.rs`, `verdigris/verdigris/Cargo.toml` | ✅ yes | `cargo test`; CI clippy |
| 2 | Gas registry adapter + de-dup reaction priorities (write, don't call yet) | new `gas_data` provider w/ `.datums`; audit `gas_types.dm` fields; `SSair.gas_reactions` priorities | code-compiles only | DreamChecker |
| 3 | `/datum/gas_mixture` → arena handle | fold `auxmos_bindings.dm` into `gas_mixture.dm` (delete dup DM bodies + `gases`); `New`/`Del` register/unregister; reconcile LINDA-only procs (`assert_gas`, `add_gas`, `garbage_collect`, `has_gas`, `archive`, `share`, `consider_pressure_difference` — many become no-ops or Rust-side) | ❌ atomic w/ 4–6 | boot |
| 4 | Reactions onto arena | `gasmixtures/reactions.dm` (get/set/adjust_moles) | ❌ atomic | boot + fire tests |
| 5 | Turf driver | rewrite `SSair.dm` fire loop → process_turfs/groups/equalize/finish + callbacks; call `auxtools_atmos_init` in `Initialize`; per-turf `update_air_ref`/`__update_auxtools_turf_adjacency_info` on init + `air_update_turf`; delete `process_cell`/`active_turfs`/excited-group DM | ❌ atomic | boot + atmos tests |
| 6 | Consumer migration | ~12 direct `.gases[` + ~67 `xgm_compat.dm` callers → arena accessors | ❌ atomic | boot |
| 7 | Verification harness | integration test: `get_amt_gas_mixes()==0` post-round; quarry decompression perf | ✅ yes | CI |

Chunks 3–6 land together. Reactions (4) and consumers (6) are where the bulk of
the per-call-site work is.

## 7. Quarry / multi-z integration

- `SSair.build_multiz_atmos_levels()` (`SSair.dm:443`) stays — it feeds the DM
  adjacency builder, which now feeds auxmos via `__update_auxtools_turf_adjacency_info`.
- `SSquarry`'s runtime `load_new_z()` path (`quarry_controller.dm:501`,
  `quarry_persistence.dm:405`) must, after loading a layer: register the new
  turfs' air (`update_air_ref`) and adjacency, then re-run
  `build_multiz_atmos_levels()`. Cave walls (`blocks_air`) auto-drop from the
  auxmos graph (register with `flag < 0`), which is the `quarry_atmos_skip`
  equivalent — inert rock costs ~0 nodes.
- Perf gate: blast a 100-tile hole in a cave layer; confirm the katmos
  decompression wave stays within SSair budget (decision §5 of atmos_migration).

## 7a. VALIDATED against the baked .so (2026-07-02, virgo/Southern-Cross boot)

Empirically confirmed on the GCP VM (see memory `ss13-gcp-vm`), so chunks 3+ build
on proven ground:

- **Gas identity = register-by-path-text.** DeepQuarry's LINDA keys gases by
  `/datum/gas/*` TYPE PATHS; auxmos maps args via `get_string()` and
  `gas_idx_from_value` does `get_strid().unwrap()` — a *raw* type path would
  **panic-crash** (not error). Solution (no Rust patch): register each gas under
  its path-TEXT (`"/datum/gas/plasma"`) via `build_auxmos_gas_registry()`, and
  DM wrappers pass the arg **stringified** (`"[gas_type]"`). Confirmed: `set_moles`
  / `get_moles` / `total_moles` / `return_pressure` round-trip (`got=100`,
  `pressure=32.05`).
- **`gas_data.datums` must be an ASSOC list** `id -> meta` (auxmos iterates
  `(_, gas)` taking the value). A flat list registers nulls.
- **STRING-EMISSION HAZARD (systemic).** auxmos looks up vars via
  `byond_string!("name")`, which **panics `NonExistentString` (crash)** if that
  var-name string was never compiled into the DM. `/tg/` combustion vars
  (`oxidation_temperature`, `fire_temperature`, `fire_burn_rate`, `fire_products`,
  `enthalpy`, `fire_radiation_released`, …) don't exist in DeepQuarry, so every
  name auxmos reads must be **declared somewhere in DM** (done on
  `/datum/auxmos_gas_meta`). This is why Task 1 (panic-safe binds) matters — until
  the binds `catch_unwind`, any missed string is an instant server crash, not a
  recoverable runtime.
- **`/datum/gas_mixture` needs `initial_volume` + `_extools_pointer_gasmixture`
  vars** (read/written by `register_mix`) — added.
- **Init sequencing:** `auxtools_atmos_init(build_auxmos_gas_registry())` is called
  in `SSair.Initialize` with `gas_reactions` temporarily emptied (reaction parse =
  chunk 4). Boot survives; gas registry populated.

## 8. Risks / watch-items

- **Silent gas corruption** if any consumer keeps reading `gases[]` after
  chunk 3. Grep must return zero `\.gases\[` hits outside gas_mixture.dm before
  boot.
- **`return_air()` mutability.** `/turf/open/return_air()` returns `air`
  directly (mutable, `LINDA_turf_tile.dm:134`); 112 callers rely on that. With
  the arena, confirm auxmos's turf air handle is still a live mutable handle,
  not a copy.
- **Reaction priority panic** at init if two DM reactions share a priority.
- **Re-vendoring auxmos** gets harder once binds are hand-wrapped for panic
  safety — prefer the forked-macro approach (§4) to keep auxmos pristine.
