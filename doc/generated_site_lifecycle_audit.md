# Generated-site lifecycle and performance audit

Scope: read-only review of the generated-station, expedition, Flight Operations,
and Verdigris station-layout paths on 2026-07-19. Generator-owned source was not
changed because active work is proceeding on another branch.

## What is sound

- The Rust station-layout entry point is a pure request/response operation. It
  retains no station arena or numeric handle after returning, so it has no
  persistent per-site Rust allocation to release.
- Expedition z-level growth is capped by `EXP_MAX_SITE_ZLEVELS`, and released
  levels are pooled for reuse.
- Site destruction clears mission, biome, station specification,
  materialization, simulation, director, defense, utility, and control datums.
- Flight plans release destination and berth leases from `Destroy()` and normal
  failure paths.
- Site release unregisters its Flight Operations destination before wiping the
  z-level.

## Findings for the generator integration branch

### High: release safety is enforced by callers, not by `release_site()`

Normal automatic and abandonment paths check `players_on_z()`, but
`release_site()` is public and immediately wipes the level. `wipe_z()` preserves
a connected mob object while replacing the turf beneath it with space and then
returns the z-level to the free pool. A future caller or test can therefore
recycle an occupied level.

Recommended invariant: `release_site()` must refuse release while any connected
client remains on the z-level. Provide a separate, explicitly named forced admin
path that first relocates clients.

### High: asynchronous generation can outlive its flight plan

`materialize_site_async()` validates the plan before generation, but generation
can yield repeatedly. If the flight plan is deleted or cancelled during that
work, the generated site may finish after its consumer has gone away. The final
plan update is guarded, but ownership/cancellation is not checked between major
generation stages.

Recommended invariant: use a generation lease/token owned jointly by descriptor
and plan. Check it after every yielding phase. Cancellation must either abort
before publication or release the newly allocated site immediately.

### Medium: no repeated allocation/release soak test

Existing integration tests exercise generation and release, but there is no
bounded loop that proves several reused generations return registries and
allocation counts to baseline.

Add a long-running test tier that records before/after values for:

- `world.maxz`, `SSexpedition.sites`, and `SSexpedition.free_z`;
- Flight Operations destinations, active plans, and reserved ports;
- generated areas, controls, defenders, objectives, and tracked furnishings;
- SSair turf handles, gas-mix handles, pipenets, powernets, machinery, timers,
  and signal registrations;
- total DM datum/atom counts and Verdigris allocation counters.

Run at least 25 generate/deploy/release cycles over several seeds and require a
stable plateau after the z-level pool reaches capacity.

### Medium: full-z scans dominate DM work

Floor discovery and wipe traverse `world.maxx * world.maxy` turfs. Materializing,
validating, furnishing, building utilities, and scanning floors also make several
passes over the station footprint. `CHECK_TICK` prevents a single uninterrupted
loop, but total generation latency and scheduler pressure remain proportional to
map area.

Carry the materializer's owned-turf set into the site result and use it for floor
selection and ordinary teardown. Retain a full-z defensive scrub only when a
level enters or leaves the reuse pool.

### Medium: timing exists only as unstructured log text

Generation logs phase timing, but teardown time, object counts, rejected seeds,
degradation causes, and post-release allocation deltas are not recorded in a
machine-readable form.

Publish structured counters through the existing profiling/admin diagnostics so
seed regressions can be compared automatically.

## Acceptance targets

- No occupied z-level can enter the free pool.
- Cancelling at every generation stage leaves no site, destination, or lease.
- The ninth concurrent request fails cleanly at the eight-level cap.
- Twenty-five sequential cycles reuse pooled z-levels without monotonic growth
  in tracked atoms, datums, timers, gas handles, powernets, or pipenets.
- Generation and teardown expose phase timings and owned-object counts.
- A failed or degraded seed reports one stable seed and actionable reason.
