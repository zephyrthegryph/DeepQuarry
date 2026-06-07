# Atmos → Rust LINDA migration

This is the plan-of-record for replacing the ZAS atmospherics in DeepQuarry
with /tg/-lineage LINDA atmospherics backed by an in-tree Rust port of
[auxmos](https://github.com/Putnam3145/auxmos). It is the authoritative
document for sequencing, decisions, and compat-layer scope.

**Status**: Phase 0 (bridge hardening) ✅. Phase 1 (vendor + scaffold) ✅.
Phase 1.5 (unconditional commit to LINDA) ✅ — ZAS/XGM deleted. **Phase 2
(make-it-actually-build)** is the active work: 806 compile errors across
166 files, each needing per-site rewriting against LINDA's APIs.

---

## Why

- **Performance.** Auxmos benchmarks 5–20× on the gas-math hot path. LINDA's
  per-tile model with active-tile skipping has a much flatter worst case
  than ZAS's zone-rebuild thrash under chaotic conditions (decompression,
  rapid door cycling).
- **Gameplay depth.** Propagating pressure waves, tile-by-tile decompression,
  propagating pipenets, a full reaction roster (plasma fires, trit, fusion,
  freon, BZ, healium, halon) are upgrades CHOMP players will feel.
- **Ecosystem.** /tg/ atmos gets PR-velocity in PRs/week; Bay-lineage atmos
  gets PRs/year. We're inheriting an actively maintained subsystem.

We accept the cost: this is a **permanent hard fork from CHOMP** on the atmos
subsystem. CHOMP atmos PRs will no longer apply. See "Upstream parity loss"
below for the durable cost.

## What we keep, what we replace

| Keep | Replace |
|---|---|
| `SSair` as the DM-side controller (rewritten internals) | `code/ZAS/` (Zone, Connection*, Airflow, Phoron, Fire) |
| `/datum/gas_mixture` as the DM-facing handle type (gutted) | `code/modules/xgm/` (gas registry) |
| `/world/proc/return_air()` convention (forwarded to LINDA) | `code/ATMOSPHERICS/datum_pipe_network.dm` |
| Atmos machinery shells (vents, scrubbers, canisters) — refit | Internal pipenet logic |
| CHOMP **lingering fires** (re-implemented as LINDA hotspot subtype) | ZAS Fire + Fire_acts |
| CHOMP **phoron medical exposure** (gas exposure damage) | Airflow shove (re-implement on top of LINDA decompression as a DQ feature) |
| Quarry atmos skip (re-implemented via `SIMULATION_LEVEL_NONE`) | XGM gas reaction system |
| TGUI canister UI (refit for LINDA gas table) | ZAS TGUI atmos console |

## Sources we vendor

We pin specific commits — we do **not** track upstream live. Update only on
demand, with parity tests.

| Source | Path in repo | Commit | License |
|---|---|---|---|
| [tgstation atmospherics DM](https://github.com/tgstation/tgstation) | `modular_dq/code/atmospherics/` | TBD (latest stable at vendor time) | AGPL-3.0 |
| [auxmos](https://github.com/Putnam3145/auxmos) | `verdigris/atmos/` (workspace member) | TBD | MIT |
| [byondapi-rs](https://github.com/spacestation13/byondapi-rs) | Transitive via auxmos | TBD | MIT |

When vendoring:

- Strip auxmos features we don't use initially: `superconductivity` (Phase 4),
  `reaction_hooks` (Phase 3), `citadel_reactions`/`yogs_reactions` (project
  policy: stick to /tg/ canonical reactions), `katmos_slow_decompression`
  (decision pending — see open questions).
- Keep enabled: `turf_processing`, `fastmos`/`katmos` (pick one — see open
  questions), `monstermos`.
- Re-export auxmos's `Mixture`, `react`, `TurfGases` through verdigris's
  `gas`/`turfs`/`reactions` modules so DM only sees `verdigris_*` symbols
  (one library, one ABI).

## Phased rollout

Each phase is its own PR (or short PR series). Don't blend phases.

### Phase 0 — Bridge hardening ✅ DONE

Done in this turn. See commit history and `verdigris/README.md`.

- Toolchain pinned (`rust-toolchain.toml`, MSRV 1.85)
- `panic_safe!` macro + global panic hook → no SIGSEGV on Rust panic
- `verdigris_init()` called from `/world/New()`
- CI builds verdigris from source on every PR
- CI runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`
- Unit tests for `random_map::seed_map` and panic payload extraction
- Build scripts (`build-linux.sh`, `build-windows.sh`) hardened to be
  invocable from anywhere
- README documents the five FFI rules

**Follow-up not done in Phase 0** (do before Phase 1.1 lands):

- `git rm --cached libverdigris.so verdigris.dll` once team is comfortable
  requiring rustup for local builds (CI builds from source now, so this is
  safe). Add the two paths to `.gitignore` afterwards.

### Phase 1 — LINDA scaffold + auxmos vendor

Goal: a parallel LINDA implementation lives in the tree, **gated off** by a
DME `#define USE_LINDA_ATMOS` so ZAS remains the live system until Phase 2.

**Phase 1.1a/b/c + 1.2a complete as of 2026-05-23.** Subsequent phase 1.2
chunks (gas_mixture skeleton, SSair, pipenets, machinery, TGUI) still
pending — see "Phase 1.2 sub-structure" below.

#### 1.1 Vendor auxmos as a workspace member

- Convert `verdigris/Cargo.toml` to a workspace root with members
  `["verdigris", "atmos"]`. Move existing crate to `verdigris/verdigris/`.
- Add `verdigris/atmos/` containing auxmos source (vendored, not submodule —
  we modify it).
- Wire feature flags per "Sources we vendor" above.
- Re-export auxmos's binds through verdigris so DM sees one library file.
- CI builds the workspace; both `libverdigris.so` and `libatmos.so` (or one
  combined) deploy to repo root.

**Decision needed before this PR**: which auxmos commit, which feature flags
(see open questions §1, §2).

#### 1.2 Vendor /tg/ atmospherics DM code

- Pick a /tg/ commit. Snapshot `code/modules/atmospherics/`,
  `code/datums/gas_mixture.dm`, the gas type definitions, the SSair
  controller, and the canister/vent/scrubber/atmos-console TGUI under
  `modular_dq/code/atmospherics/` and `modular_dq/tgui/`.
- Adapt **paths only** (BYOND `tg` namespacing differs from CHOMP). Don't
  refactor — keep it as close to /tg/ as possible to ease future cherry-picks.
- Wire all of it behind `#ifdef USE_LINDA_ATMOS` so the build still works
  with ZAS as primary.
- Add the imported files to `vorestation.dme` inside a clearly-marked block:
  ```
  // BEGIN LINDA ATMOS — see modular_dq/doc/atmos_migration.md
  #ifdef USE_LINDA_ATMOS
  #include "modular_dq\code\atmospherics\..."
  #endif
  // END LINDA ATMOS
  ```

#### 1.3 Compat shims

- `/datum/gas_mixture` becomes a thin DM wrapper holding a `_handle` (arena
  index). All existing `gas[]` getter/setter call sites continue to work via
  the wrapper. Mark every upstream `code/` file we touch with
  `// DQEdit Start — LINDA atmos integration` / `// DQEdit End`.
- `return_air()` proc on `/turf` and `/atom` forwards to LINDA when
  `USE_LINDA_ATMOS` is defined.
- Mapping table: ZAS `XGM_GAS_*` defines → LINDA `GAS_*` defines. Keep both
  alive during transition.

**Exit criteria for Phase 1**: with `USE_LINDA_ATMOS` defined, server starts,
no atmos errors at init, both systems compile in parallel. ZAS is still live.

### Phase 2 — Cutover on a single test map

- Build a minimal test map (`modular_dq/maps/atmos_test.dmm`) that exercises
  rooms, doors, pipes, vents, scrubbers, fire, decompression, plasma reaction.
- Enable LINDA only on that map (per-map define gate).
- Iterate until atmos integration tests pass on the test map.
- Add CI integration tests for LINDA-specific behaviors.

**Exit criteria**: full atmos test passes on test map; ZAS still default on
production maps.

### Phase 3 — Main map cutover (one at a time)

CI matrix currently builds `USE_MAP_SOUTHERN_CROSS`, `USE_MAP_SOLUNA_NEXUS`,
`USE_MAP_CETUS`. Migrate one at a time:

1. Pick smallest first (probably Cetus). Audit atmos turfs: every
   `/turf/simulated/floor` → `/turf/open/floor` shape, every `/turf/space` →
   `/turf/open/space`, atmos object paths remap.
2. Use mapmerge2 + a custom Python remap script (under `tools/`) to do the
   bulk rename. Manual review of edge cases (vents/scrubbers connected to
   atmos console).
3. Re-validate the map: place it on LINDA, check pressure, fire behavior,
   pipenet flow visually.
4. Land the map cutover, ZAS removed for that map.
5. Repeat for next map.

**Exit criteria per map**: integration tests pass, atmos demo round runs
clean.

### Phase 4 — Retire ZAS

After all maps are on LINDA:

- Delete `code/ZAS/` entirely.
- Delete `code/modules/xgm/`.
- Delete `code/ATMOSPHERICS/datum_pipe_network.dm`.
- Delete the `USE_LINDA_ATMOS` define and the `#ifdef` gates.
- Delete the compat shims in `/datum/gas_mixture`.
- Move LINDA code from `modular_dq/code/atmospherics/` to its natural home
  (still under `modular_dq/` to keep the modular-fork discipline, but
  ungated).
- Re-implement CHOMP-specific behaviors as LINDA-side modules:
  - **Lingering fires** (CHOMP's slow-burn): new `/obj/effect/hotspot/lingering`
    subtype with longer decay, persistent state.
  - **Phoron medical exposure**: keep as a `/datum/medical_issue/condition`
    triggered by gas exposure (already structured this way in
    `modular_dq/code/modules/medical/conditions/respiratory.dm`).
  - **Airflow shove** (Bay flavor — optional): port from ZAS as a LINDA
    decompression hook if the team misses the dramatic mob-throw effect.
    Otherwise drop.
- Update CLAUDE.md to note that atmos is now LINDA/Rust-backed.

### Phase 5 — Profile-driven optimization

Only after Phase 4 ships. Profile a busy round:

- Is `SSair.fire()` budget healthy?
- Pipenet processing?
- Hotspot count under sustained fires?
- Boundary call count per tick?

Tune from here. The auxmos `katmos`/`fastmos`/`monstermos` flags affect
performance characteristics — A/B test.

## Compat shims that need design before Phase 1.3

These are the seams where ZAS and LINDA differ structurally and where the
shim layer has to be thought through, not just code-translated:

1. **`return_air()`** — ZAS returns the zone's air; LINDA returns the turf's
   gas. Behaviorally identical for single-turf queries but breaks for
   "what's the air in this whole room?" code paths (`get_room_pressure()`,
   etc.). Audit all callers; convert "room" queries to "this turf" queries
   or aggregate explicitly.
2. **Zone-level fire** — ZAS's `zone.process_fire()` processes a whole zone;
   LINDA processes per-tile hotspots. CHOMP code that asks "is this room on
   fire?" needs reformulation to "is any tile in this area on fire?"
3. **Airflow shoves** — ZAS's `AIRFLOW_MOVE` doesn't exist in LINDA. Either
   port the shove logic onto LINDA decompression events, or accept that mobs
   stop getting yanked toward breaches (LINDA does throwing but more
   measured).
4. **Pipenet timing** — ZAS reconciles pipenets instantly; LINDA propagates
   over time. Atmos engineering interfaces (canisters, port-a-brigs, etc.)
   that assume "fills instantly" will behave differently. May actually be
   the *intended* upgrade — preheating burn chambers is a real LINDA skill.
5. **Group multiplier** — ZAS's `gas_mixture.group_multiplier` (multiple
   turfs share one mixture, scaled by count) doesn't exist in LINDA (each
   turf has its own). Affects `total_moles` semantics. The compat layer must
   present the right value to legacy consumers.

## Quarry-specific concerns

DeepQuarry's signature feature is procedurally generated 256×256 cave layers
(`modular_dq/code/modules/quarry/`). That's 65k tiles per layer. ZAS handles
this well: `modular_dq/code/modules/quarry/quarry_atmos_skip.dm` skips zone
init for cave walls.

LINDA equivalent:

- Cave wall turfs map to a **non-simulated** atmos type (`SIMULATION_LEVEL_NONE`
  or auxmos's "planet atmos" / "space" tile classes — TBD).
- Auxmos's `TurfGases` is a `StableDiGraph<TurfMixture, AdjacentFlags>`:
  inert/space turfs aren't nodes, so 65k inert tiles cost ~0.
- **Edge case**: when a quarry tile is mined and exposed to the cave
  atmosphere, the LINDA frontier activates. Audit `quarry_atmos_skip.dm`
  callers to ensure the simulation-level transition is correct.
- Performance test specifically: blast a hole into a 100-tile cave area on a
  quarry map. Ensure the pressure-wave activation doesn't spike SSair beyond
  budget. If it does, increase tile chunk size in monstermos or accept the
  brief frame budget overrun (decompression is rare).

## Upstream parity loss

The day Phase 4 ships, CHOMP atmos PRs no longer apply. Things we will need
to re-port (or accept as lost) on an ongoing basis:

- Bug fixes in `code/ZAS/` from CHOMP/Polaris/Bay (lost — different engine).
- New gas types added upstream in `code/modules/xgm/` (lost — we use /tg/
  gases now).
- Map atmos retunings from CHOMP (have to evaluate per-PR whether they make
  sense under LINDA).
- New atmos machinery upstream (have to re-implement against LINDA's
  pipenet API).

Estimate: a few hours per quarter to manually re-port CHOMP atmos changes
that we actually want. Most upstream atmos PRs will simply not apply.

## Decisions (locked 2026-05-23)

1. **auxmos feature flag**: `katmos` (auxmos default).
2. **auxmos commit pin**: master HEAD at vendor time. Record the commit hash
   in `verdigris/atmos/UPSTREAM.md` so we know what we have.
3. **/tg/ snapshot commit**: whichever /tg/ commit is compatible with the
   auxmos HEAD we vendor (gas types and `GAS_*` defines must match — see
   auxmos's `src/gas/types.rs`). Determine at Phase 1.2 import time.
4. **One library**. auxmos becomes an `rlib` (not `cdylib`) and links into
   `libverdigris.so`. DM only loads one library.
5. **`katmos_slow_decompression`**: enabled. More dramatic breach feel.
6. **Reactions: keep current CHOMP/XGM reactions, do not import /tg/'s
   roster.** This is the architectural constraint that distinguishes our
   migration. Implications:
   - No BZ, healium, halon, trit fusion, freon cooling, plasma fires, etc.
     Only what XGM currently models: phoron combustion + oxidizer reactions
     + CHOMP-specific reaction extensions.
   - auxmos's default `reaction_hooks` is **disabled**; we will reimplement
     XGM's reactions on top of LINDA's gas mixture in `verdigris/atmos/src/reactions/dq.rs`
     (or keep reactions in DM and let auxmos do only the gas-flow plumbing —
     decide when porting `zburn`).
   - Gas types in LINDA must be remapped from /tg/'s set (`/datum/gas/oxygen`,
     `plasma`, `nitrogen`, `co2`, `n2o`, `bz`, ...) to CHOMP's XGM set
     (oxygen, phoron, nitrogen, carbon_dioxide, nitrous_oxide, ...). We
     keep CHOMP names; auxmos's gas registry is rebuilt from our list at
     boot.
7. **CHOMP atmospherics machinery in `modular_chomp/`**: remove the engine
   code, keep the features.
   - Delete: `modular_chomp/code/ZAS/Fire.dm` (engine code).
   - Keep & re-implement on LINDA: lingering fire system (subtype of
     `/obj/effect/hotspot`), phoron medical exposure (via medical
     conditions, already in `modular_dq/code/modules/medical/conditions/respiratory.dm`).
   - Audit `modular_chomp/code/ZAS/Fire_acts.dm` for object burn-reaction
     macros worth keeping.
8. **Untrack `libverdigris.so` / `verdigris.dll`**: yes. Done in Phase 1.1a.
   `git rm --cached`; CI builds from source. Local Rust development now
   requires `rustup` (DM-only contributors can still run the server with a
   CI-built artifact).

## Sub-phase structure for Phase 1.1

- **1.1a — Workspace prep** ✅ **DONE 2026-05-23**: binaries untracked,
  verdigris is now a workspace.
- **1.1b — Vendor auxmos** ✅ **DONE 2026-05-23**: auxmos at commit
  `7757b8e` vendored into `verdigris/atmos/`. cdylib → rlib, panic=abort
  removed, mimalloc global_allocator removed, one upstream bugfix in
  `katmos.rs` (see UPSTREAM.md). Workspace builds clean.
- **1.1c — Re-export bindings** ✅ **DONE 2026-05-23**: `use auxmos as _;`
  in `verdigris/src/lib.rs` forces auxmos's `#[byondapi::bind]` exports
  to land in the final cdylib. **Validated**: i686-pc-windows-msvc
  `cargo build --release` produces a 1.2 MB `verdigris.dll` exporting 112
  auxmos FFI symbols + 4 verdigris symbols. The "one library" goal (Q4)
  is achieved.

### What 1.1c did NOT do

- Patch each auxmos `#[byondapi::bind]` to wrap in our `panic_safe!`.
  Byondapi-rs's bind macro is believed to already provide catch_unwind
  panic safety (verify before relying on it). If a hot atmos function
  panics in production and crashes DreamDaemon, this is the first place
  to investigate.

### Phase 1.2 sub-structure

- **1.2a — Bindings scaffold** ✅ **DONE 2026-05-23**:
  - `modular_dq/code/__defines/atmospherics.dm` declares the
    `USE_LINDA_ATMOS` gate (commented-out by default).
  - `modular_dq/code/atmospherics/auxmos_bindings.dm` autogenerated from
    `cargo t generate_binds`, post-processed to route through the
    `VERDIGRIS` library (not a separate `AUXMOS`). 241 lines, hooks into
    `/datum/gas_mixture/*`, `/datum/controller/subsystem/air/*`, and
    `/turf/*` procs.
  - `tools/verdigris/generate_atmos_bindings.sh` regenerates the bindings
    portably (auto-detects Linux vs Windows for the i686 target).
  - CI in `run_integration_tests.yml` regenerates the bindings after each
    verdigris build and `git diff --exit-code`s for drift.
  - Include in `vorestation.dme` is gated behind `#ifdef USE_LINDA_ATMOS`.
    Default builds (USE_LINDA_ATMOS undefined) are untouched.
- **1.2b — gas_mixture skeleton** ✅ **DONE 2026-05-23**: vendored
  `/tg/`'s `code/modules/atmospherics/gasmixtures/` (5 files,
  ~3,000 lines) verbatim into `modular_dq/code/atmospherics/gasmixtures/`.
  Includes gas_mixture.dm, gas_types.dm, immutable_mixtures.dm,
  reaction_factors.dm, reactions.dm. Gas TYPES are /tg/'s default set;
  per Q6 we'll remap to CHOMP gases when porting reactions.
- **1.2c — Atmos defines** ✅ **DONE 2026-05-23**: vendored
  `code/__DEFINES/atmospherics/` (7 files, 805 lines) into
  `modular_dq/code/__defines/atmospherics_linda/`. TCMB, CELL_VOLUME,
  MOLES/ARCHIVE/GAS_META indices, etc.
- **1.2d — SSair controller** ⏳ **PARTIAL**: vendored
  `/tg/`'s `code/controllers/subsystem/air.dm` (935 lines) as
  `modular_dq/code/atmospherics/SSair.dm`. Wired into the include block.
  **NOT YET DONE**: auxmos init hook — `SSair.Initialize()` needs to call
  `verdigris_init()` before any auxmos bind fires. Add a `// DQEdit` to
  the vendored file or hook via a separate `SSair.Initialize` override.
- **1.2e — Pipenets** ✅ **DONE 2026-05-23**: included with machinery
  (`machinery/datum_pipeline.dm` and `machinery/pipes/`).
- **1.2f — Machinery** ✅ **DONE 2026-05-23**: vendored `/tg/`'s
  `code/modules/atmospherics/machinery/` (65 files, ~16,000 lines):
  vents, scrubbers, canisters, fusion reactor (HFR), crystallizer, air
  alarm, atmos control console, pipes, portables. All gated.
- **1.2g — TGUI** ⏳ **NOT STARTED**: /tg/'s atmos TGUI interfaces (8
  files: `AirAlarm/`, `AtmosControlConsole.tsx`, `Canister.tsx`,
  `common/AtmosHandbook.tsx`, `GasAnalyzer.tsx`) plus the supporting
  TGUI components they reference. The TGUI build pipeline picks files
  up from `tgui/packages/tgui/interfaces/`, so they'd land in
  `modular_dq/tgui/...` once the project's TGUI workspace is configured
  to scan modular folders. Defer to a separate PR.
- **1.2h — XGM/ZAS engine ifdef-gating** ⏳ **PARTIAL**:
  - ✅ `code/modules/xgm/xgm_gas_data.dm` and `xgm_gas_mixture.dm`
    gated with `#ifndef USE_LINDA_ATMOS` in `vorestation.dme:5224-5225`.
  - ✅ `code/ZAS/*.dm` (12 files) gated similarly.
  - ✅ `modular_chomp/code/ZAS/Fire.dm` and `Fire_acts.dm` gated.
  - ⏳ **NOT YET**: every CHOMP file that *consumes* ZAS/XGM types
    (mob breath code, fire code, life code, area air handling,
    canister/vent machinery, etc.) still references types like
    `/datum/zone`, `/datum/connection_edge`, `GAS_PHORON` define, etc.
    Under `USE_LINDA_ATMOS=1` these will produce ~hundreds of compile
    errors. The Phase 4 (Retire ZAS) sub-step is where these are
    resolved — likely via mass-replace plus careful adaptation.

### Vendor totals (Phase 1.2 b/c/d/e/f as of 2026-05-23)

- Files vendored from /tg/ commit `5121e01bec7bdc1d9309cfb88e97e3397999b8bb`
  (2025-XX master HEAD): 80+ DM files, ~26,000 lines.
- All under `#ifdef USE_LINDA_ATMOS` so default builds (ZAS) are
  unaffected. **DM compile of the default branch verified passing** with
  the full vendor in place.
- Auxmos bindings.dm continues to be autogenerated and post-processed by
  `tools/verdigris/generate_atmos_bindings.sh` and drift-checked in CI.

### Iteration snapshot (2026-05-23 attempt at LINDA-branch compile)

Briefly turned on `USE_LINDA_ATMOS` to drive dm.exe and capture errors:

- **Round 0** (just scaffold + ZAS gated): 2,907 errors
- **Round 1** (gated CHOMP atmos engine: SSair, airflow, ATMOSPHERICS/, gases.dm; stripped LINDA machinery from active includes): 2,378 errors
- **Round 2** (gated whole `code/ATMOSPHERICS/` block 556–604): 1,584 errors
- **Round 3** (gated 9 more individual CHOMP consumers via DME `#ifndef`: cryo, clamp, life, generator, etc.): 1,388 errors
- **Round 4** (added `xgm_compat_shim.dm` with proc-call shims on /datum/gas_mixture: adjust_gas, update_values, update_nearby_tiles, add_thermal_energy, get_by_flag, update_graphic_xgm): 1,345 errors
- **Round 5** (expanded shim with /atom/movable/proc/update_nearby_tiles, /turf/proc/update_graphic, /turf/proc/c_airblock, /datum/controller/subsystem/air shims, /turf/proc/assume_gas, /turf/proc/return_air_for_internal_lifeform): 1,205 errors
- **Round 6** (vendored /tg/'s `code/__DEFINES/reactions.dm` for FREON_* etc., added /datum/xgm_gas_data stub global, added adjust_gas_temp/specific_entropy/remove_volume shims): 948 errors
- **Round 7** (moved return_air_for_internal_lifeform shim from /turf to /atom, removed auxmos_bindings.dm from active include — /tg/'s gas_mixture.dm provides the DM bodies, byondapi swaps at runtime; added IS_FINITE / GET_TURF_PLANE_OFFSET / GLOB.electrolyzer_reactions stubs): **915 errors**

**Net reduction: 2,907 → 803 (72%) across 12 iterations + 2 hand-migrations.**

- **Round 10–11** (extended rewriter with `LINDA_GAS_AMT` covering variable gas-IDs + `LINDA_GAS_LIST` for whole-list refs; discovered DM preprocessor doesn't handle `MACRO(x).member` — reverted LINDA_GAS_LIST; removed `total_moles → total_moles()` from rewriter since XGM/LINDA can't be bidirectionally shimmed for var/proc collisions): 832 → 804.
- **Round 12** (added `xgm_total_moles(mix)` global proc as the bidirectional bridge for the var/proc collision case; hand-migrated `alraune.dm` (10 errors → 0) and `supermatter.dm` (8 of 9 errors → 0) using the helper + `LINDA_GAS_AMT` macro + targeted `#ifdef USE_LINDA_ATMOS` for ZAS-specific concepts like `group_multiplier` and airflow procs; added `xgm_total_moles_test.dm` unit test that exercises the bridge in both builds): **803 errors / 165 files remaining**.

### Round 13 — UNCONDITIONAL LINDA (2026-05-23)

User direction: **stop gating, commit to LINDA permanently, no fallback.**

- `tools/verdigris/unconditional_linda.py` stripped all `#ifdef USE_LINDA_ATMOS` /
  `#ifndef USE_LINDA_ATMOS` gates from `vorestation.dme`. LINDA includes are
  unconditional; XGM/ZAS includes deleted from build entirely.
- `USE_LINDA_ATMOS` define removed from `modular_dq/code/__defines/atmospherics.dm`.
  `LINDA_GAS_AMT`, `LINDA_GAS_ADJUST`, `xgm_total_moles`, `IS_FINITE`,
  `GET_TURF_PLANE_OFFSET` are all unconditional LINDA-side definitions.
  No more bidirectional shims.
- **ZAS/XGM engine source files DELETED from the tree** (68 file deletions):
  - `code/ATMOSPHERICS/` (entire dir — CHOMP pipenet machinery)
  - `code/ZAS/` (entire dir — ZAS engine)
  - `code/modules/xgm/` (entire dir — XGM gas system)
  - `code/_helpers/atmospherics.dm` (ZAS helpers)
  - `code/controllers/subsystems/air.dm` (CHOMP SSair)
  - `code/controllers/subsystems/airflow.dm` (ZAS airflow processor)
  - `code/defines/gases.dm` (XGM gas decls)
  - `modular_chomp/code/ZAS/Fire.dm` + `Fire_acts.dm` (CHOMP lingering fire overrides)
- `tools/verdigris/apply_linda_dme_edits.py` deleted (re-applied the gating we
  just stripped — harmful).
- Default-build mode is gone. There is no XGM build. **`dm.exe -o vorestation.dme`
  now reports 806 errors** — these are the legitimate per-call-site rewrites
  the migration still needs.

The committed state: LINDA is the only atmos engine. The build does not compile
clean. The 806 errors are the punch list to clear before the game can launch.

### Hand-migration pattern (validated on alraune.dm, supermatter.dm)

For each CHOMP file that touches XGM:

1. **`mix.total_moles` var read** → `xgm_total_moles(mix)` global proc call.
2. **`mix.gas[GAS_X]` / `mix.gas["string"]` read** → `LINDA_GAS_AMT(mix, GAS_X)` macro.
3. **`mix.gas[X] += delta`** → `LINDA_GAS_ADJUST(mix, X, delta)` macro.
4. **`mix.gas[X] = value`** → `mix.adjust_gas(X, value - LINDA_GAS_AMT(mix, X))` (XGM-side has `adjust_gas` natively).
5. **ZAS-only concepts** (`group_multiplier`, airflow procs, zones, pipe networks) → wrap call site in `#ifdef USE_LINDA_ATMOS` / `#else` with a per-site LINDA equivalent or no-op.
6. **Whole-list `mix.gas` references** (existence check, iteration, `.len`) → leave as-is; DM preprocessor can't shim. Per-site rewrite at real LINDA cutover.

Each migrated call site gets a `// DQEdit` marker explaining the change. The
result compiles under both `USE_LINDA_ATMOS` defined and undefined.

### Unit test pattern

`modular_dq/code/unit_tests/xgm_total_moles_test.dm` shows the pattern:

- Test sits behind `#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)` (auto via _unit_tests.dm include).
- Uses `TEST_ASSERT_EQUAL`, `TEST_ASSERT_NOTNULL`, etc.
- Branches on `USE_LINDA_ATMOS` only where the gas-add API genuinely differs.
- Validates: null-safety, empty-mixture, single-gas, multi-gas additive.

To run: `bin/test.cmd` (CHOMP's test runner; builds with `-DUNIT_TESTS` and
launches dreamdaemon to execute). I could not run this from here — verifying
behavior requires launching the server. Compile-time validation only via
`dm.exe -o vorestation.dme` (passes cleanly with the test).

### Why I'm stopping

165 files remain in the LINDA-on error log. Each takes 5–30 minutes of careful
per-site work that requires:

- Understanding both XGM and LINDA semantics for the call site.
- Choosing between `xgm_total_moles` helper, `LINDA_GAS_AMT` macro, `#ifdef`
  branch, or a per-site rewrite.
- Adding a unit test if the behavior is non-trivial.
- Running the test to actually verify behavior (requires running the server).

I've done two of these properly (alraune, supermatter) in this turn. Continuing
the other 163 at the same care level is ~30–60 hours of work — multiple weeks
for a single engineer working full-time. Doing them mechanically without
verification is what kept failing in earlier rounds.

The realistic path forward is per-subsystem PRs done by an engineer who can run
the game:
- Mob breath code (life.dm, species/* — uses xgm_total_moles + LINDA_GAS_AMT pattern)
- Atmos machinery (canister, vents, scrubbers — likely use #ifdef branches since ZAS pipe_network has no LINDA equivalent in our vendor)
- Fire/hotspot code
- Map atmos turfs (mapmerge-tool work, not source rewrites)
- Mob life/breath integration with LINDA reactions

- **Round 8** (`tools/verdigris/linda_rewrite_xgm_callsites.py` did 157 mechanical regex rewrites across 41 CHOMP files: `mix.gas[GAS_X]` reads → `LINDA_GAS_AMT(mix, GAS_X)` macro; `mix.gas[GAS_X] += d` → `LINDA_GAS_ADJUST(mix, GAS_X, d)`; `mix.total_moles` var-reads → `mix.total_moles()` proc calls. First attempt of the script had a regex bug — it matched `==` as assignment, garbled comparisons. Reverted, fixed lookahead/lookbehind for op-equals, re-ran cleanly): 915 → 773.
- **Round 9** (the rewrites broke the default (XGM) build because `LINDA_GAS_AMT` wasn't defined when `USE_LINDA_ATMOS` was off, and `total_moles` is a var on XGM's gas_mixture so calling it as `.total_moles()` errors. Added `#else` branch in atmospherics.dm so `LINDA_GAS_AMT` forwards to `.gas[X]` in default builds; reverted the `.total_moles()` rewrites via `tools/verdigris/linda_revert_total_moles.py`. Moved `IS_FINITE` / `GET_TURF_PLANE_OFFSET` macros to atmospherics.dm so they're in scope for the vendored /tg/ atmos files that use them): **default build clean (0 errors), LINDA build at 832 errors.**

A failed Round 2.5 (bulk auto-gate 186 CHOMP files via Python script) was
reverted — gating cascaded into turfpack/admin/hydroponics breakage because
gated files exported non-atmos helpers too. The DME edits are now captured in
`tools/verdigris/apply_linda_dme_edits.py` (idempotent, reapplies the
hand-curated gate set).

Latest snapshot: `modular_dq/doc/linda_compile_errors_by_file.txt` and
`linda_compile_errors_by_message.txt`.

### Why iteration plateaued

The remaining 915 errors are dominated by **var-access** patterns that
can't be shimmed in DM (no computed-property getters):

- `mixture.gas[GAS_O2]` — CHOMP reads gas moles as a list-keyed var. LINDA stores in `mixture.gases[/datum/gas/oxygen][MOLES]`. Per-call rewrite.
- `mixture.total_moles` — CHOMP reads as a var; LINDA exposes as a proc. Per-call rewrite.
- ZAS-only type vars: `T.zone`, `pipe.network`, etc. — types don't exist under LINDA. Per-call rewrite or ifndef-gate each containing file.

Plus a long tail of CHOMP files (~150) that touch atmos via these vars and
need per-file work. Bulk-gating fails (cascades — see Round 2.5).

The remaining 915 is the *true* size of the per-file adaptation task. Each
file is 1–25 errors; most are 1–5. A focused engineer can clear 20–30 files
per day with care.

The remaining 1,388 errors fall into three buckets, none of which compress
into single-commit fixes:

1. **~700 errors in vendored /tg/ atmos files** (modular_dq/code/atmospherics/*)
   referencing /tg/-specific infrastructure not vendored:
   `INVESTIGATE_ATMOS`, `COMSIG_*` signals, `PORT_TYPE_*` (integrated
   circuits), `NO_NEW_GAGS_PREVIEW_1` (sprite system), `GLOB.meta_gas_info`,
   etc. Either vendor more /tg/ infrastructure (large) or stub each one.

2. **~500 errors in CHOMP consumers calling XGM API on now-LINDA mixtures**:
   `environment.gas[GAS_O2]` (XGM list shape) vs `environment.gases[/datum/gas/oxygen][MOLES]`
   (/tg/ shape). Per-site rewrite — touches hundreds of call sites across
   mob breath, fire, life code, machinery, areas, planets, etc.

3. **~200 errors in CHOMP consumers extending ZAS-only types** (zone,
   connection_edge, pipe_network) — these can be gated via `#ifndef
   USE_LINDA_ATMOS` per file, but there are ~50 such files; same pattern
   as Round 3 but more.

The vendor + gating work that landed leaves the LINDA scaffold structurally
complete and the default build clean, but `USE_LINDA_ATMOS=1` will not
compile in a useful state without items 1–3. Each is its own multi-PR
adaptation effort. **Phase 4 of the migration roadmap is where this work
naturally lives** — it's the same per-file consumer adaptation that needs
to happen when ZAS is actually retired, and doing it before then means
maintaining ifdef'd parallel implementations.

Recommendation: stop at "scaffold + gates clean", treat further per-file
adaptation as the Phase 4 sub-tasks, sequenced after the gas type remap
(Q6) and SSair init wiring are designed.

### What's needed for `USE_LINDA_ATMOS=1` to compile clean (Phase 1.2 finale)

The vendor is a snapshot of /tg/'s atmos code. To actually build, we
still need to bridge /tg/'s assumptions and CHOMP's environment:

1. **/tg/ macro/helper deps**: many files use `PROC_REF`, `TYPE_PROC_REF`,
   list/string helpers, the `LAZYINITLIST` macro variants, `COMSIG_*`
   signals that differ between /tg/ and CHOMP. Identify each (via
   `dreamchecker` output under `USE_LINDA_ATMOS=1`) and either vendor
   the /tg/ definitions or adapt to CHOMP equivalents.
2. **/tg/ globals**: `GLOB.meta_gas_info`, `GLOB.gaslist_cache`,
   `SSair`'s expected APIs need wiring.
3. **/tg/ component system**: pipenets use `/datum/component/*` patterns
   that may differ; CHOMP has its own component system.
4. **Mob breath/life code**: `/mob/living/carbon/proc/breathe()` etc.
   read gas mixtures via XGM today. Either ifdef-branch in those callers
   or rewrite to call through the new LINDA proc surface.
5. **Area air**: `/area/proc/air_doesnt_exist` and zone-based area
   queries reframed.
6. **Fire**: `/obj/fire/*` (CHOMP) → LINDA hotspot subtype with
   lingering-fire feature re-implemented atop LINDA's per-tile hotspot.
7. **Map turf types**: `/turf/simulated/floor/*` → `/turf/open/floor/*`
   shapes for atmos-relevant turfs; mass-remap via mapmerge tooling.
8. **Gas type remap (Q6)**: replace /tg/'s `/datum/gas/plasma` etc. with
   CHOMP's gas roster while keeping LINDA's metadata model. Register
   with auxmos at `SSair.Initialize`.
9. **TGUI**: vendor the 8 atmos TGUI interfaces and any supporting
   imports.

Each of items 1–9 is its own landable chunk. Phase 1.2 is **structurally
complete** but the LINDA branch is not yet bootable. Phase 2 begins
when the build is bootable end-to-end.

## When to break ground on Phase 1.2

Phase 1.2 (vendor /tg/ atmospherics DM code) needs §3 resolved (the
matching /tg/ commit), and §6's gas-type remapping plan. Both are best
done in the same sitting as 1.2 lands.
