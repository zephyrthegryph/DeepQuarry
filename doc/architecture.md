# DeepQuarry architecture

DeepQuarry is a hard fork with one DM source tree. The live game is built around
Southern Cross, carrier-based flight operations, dynamically allocated expedition
sites, LINDA atmospherics, and the in-tree Verdigris Rust extension.

## Target architecture

A full rewrite is planned: one Rust simulation core, one scheduler, and unified containment, rules, interactions, damage and temperature. The design and the work items are in `doc/rewrite/README.md` and `doc/rewrite/roadmap.md`. This document describes the runtime as it is today, and it changes as each track lands.

## Runtime boundaries

- DM owns game objects, subsystem scheduling, maps, missions, UI backends, and
  lifecycle decisions.
- Verdigris owns auxmos gas arithmetic, turf-atmos processing, cave generation,
  and the pure station-layout calculation exposed through FFI.
- TGUI owns interactive browser interfaces. DM remains authoritative for every
  state transition and validates all submitted actions.
- `deepquarry.dme` is the compile manifest. New DM files are not discovered
  automatically.

## Active gameplay path

`SSflight_operations` owns destinations, vessels, berths, and flight plans.
`SSexpedition` owns expedition descriptors, materialized sites, dynamically
allocated z-levels, and site recycling. Generated stations are one expedition
site implementation; their planner and materializer are intentionally isolated
behind a specification/result contract.

## Atmospherics

LINDA is the only turf and pipe framework. Gas mixtures are Rust arena handles,
and SSair dispatches turf sharing, excited groups, and pressure equalization to
auxmos. DM still owns reactions, hotspots, machinery, pipenets, visual callbacks,
and game effects caused by pressure or fire.

Compatibility procs under `code/ATMOSPHERICS/` support remaining callers from the
older code lineage. They are migration boundaries, not alternative atmos engines.
New code should use native LINDA APIs.

## Development gates

- `bin/build.cmd` validates DME reachability, repacks icons, builds Verdigris when
  stale, and compiles.
- DreamChecker is required for DM changes. The build searches `PATH`,
  `DREAMCHECKER_EXE`, and `%USERPROFILE%/SpacemanDMM/dreamchecker.exe`.
- `bin/test.cmd` compiles and boots the unit-test world. `doc/testing.md` covers
  focused runs, the full-map run, performance profiles, and every CI check.
- TGUI changes must pass type checking, tests, and Biome lint.

## Design rules

Prefer state datums, components, elements, and signals over adding unrelated
state to base atoms. Subsystems own global collections and lifecycle. Objects
that register signals, schedule timers, or hold external handles must release
them in `Destroy()`. Dynamic-z features must prove that repeated allocation and
release returns all tracked state to baseline.

Historical architecture audits were removed after their major findings landed;
git history retains them. Current unresolved generated-site lifecycle and
performance risks are tracked in `doc/generated_site_lifecycle_audit.md`.
