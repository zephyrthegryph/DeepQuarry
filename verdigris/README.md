# Verdigris

In-tree Rust extension for DeepQuarry. BYOND loads it through `call_ext`
([`byondapi`](https://crates.io/crates/byondapi)). DM never calls `call_ext`
itself: every Rust function declared with `#[auxmacros::bind]` gets a generated
`/proc/vg_<fn>(args)` in `code/__defines/verdigris/_bindings.dm`, which caches
its `load_ext` handle. Regenerate with `tools/build/build.sh verdigris-bindings`;
the build and CI fail when the file is stale, and `check_grep.sh` rejects
`call_ext` anywhere else.

## Workspace layout

This directory is a Cargo workspace that produces one `libverdigris.so` /
`verdigris.dll`, so BYOND only ever loads one library. The target structure is
described in `doc/rewrite/rust_core.md`.

```
verdigris/                  <- workspace root (this dir)
├── Cargo.toml              <- [workspace] + shared deps and profiles
├── Cargo.lock              <- committed (we produce a final cdylib)
├── rust-toolchain.toml     <- stable + i686 targets
├── build-linux.sh / build-windows.sh
├── core/                   <- vg-core: the driver (World) and every generic
│                              facility (doc/rewrite/rust_architecture.md §8.4).
│                              Host-buildable, no byondapi, no global statics.
├── domains/
│   ├── gas/                <- vg-gas: the gas domain (M1b): turf gas field,
│   │                          pipe network, the gas world and its binds; i686
│   │                          only until its binds move to vg-ffi. Also holds the
│   │                          heat binds (heat.rs). Mixture maths vendored from
│   │                          auxmos (domains/gas/UPSTREAM.md).
│   ├── heat/               <- vg-heat: the heat domain (M4): turf solid field,
│   │                          heat bodies, couplings, regulator. Host-buildable.
│   └── power/              <- vg-power: the power domain (M3): cables as an R7
│                              network kind, the ledger, APC and SMES models.
├── gen/
│   └── layout/             <- vg-layout: the procedural generator (station
│                              layout planner, cave generator, offline tools in
│                              src/bin/). Not a sim domain: exempt from the
│                              domain rules and budgets.
├── ffi/                    <- vg-ffi: BYOND binds (the World and the generic
│   │                          component binds, lifecycle, layout, cave gen)
│   │                          and the tracking allocator; i686 only. Depends on
│   │                          the domains, never the reverse.
│   ├── macros/             <- auxmacros: #[bind] / #[bind_raw_args], the one bind macro
│   └── callback/           <- auxcallback: deferred callbacks to the main thread
├── verdigris/              <- the DLL: links vg-ffi + vg-gas, sets the global
│                              allocator; still holds material_power.rs
├── tools/bench/            <- vg-bench: criterion benchmarks
└── tools/replay/           <- vg-replay: replays a flight-recorder log, checks state hashes
```

## Modules

| Crate / module | Purpose |
|---|---|
| `vg-ffi` `world` | The DLL's one `World`, the registration list (every domain's components, laws, networks), and the generic binds `vg_component_*` / `vg_world_*` (`doc/rewrite/rust_bindings.md` §17). |
| `vg-core` `world` | The driver: one `World` owning identity, component stores, networks, globals, the grid, fields, pacing, laws (as frame tasks, main or worker phase), typed events, watches and the conservation check. |
| `vg-core` `law` / `query` | `Law`/`LawCtx`/`Effects`/`Settle`/`Period`, `order_laws`, `Pacer`; `Query`/`WriteQuery` over components, `Option`, `Global`, network payloads/sides/members, field cells. |
| `vg-core` `component` / `store` | The `Component` trait `#[vg::component]` implements (field ids, generic get/set/adjust, conserved fields), the domain id table; stores indexed by entity slot (`Rows`, `MainKind`, `WorkerKind`). |
| `vg-core` `event` / `registry` | The typed event codec (`Event`, `EventSink`, the one wire format); the `DomainRegistry` trait and table. |
| `vg-ffi` `lifecycle` | `verdigris_init`, `cleanup`, version/feature metadata, allocator diagnostics. |
| `vg-layout` `random_map` | Cellular-automata cave generator used by expedition sites. |
| `vg-layout` `station_layout` | Generated-station layout planner; planning runs as a `vg-core` job (`plan_catalog_job`). |
| `vg-ffi` `jobs` | The DLL's job registry and the generic job binds (`verdigris_job_poll` / `_progress` / `_cancel` / `_finish`, `verdigris_jobs_completed`). |
| `vg-ffi` `metrics` | The DLL's metrics registry and `verdigris_metrics()`, which returns every Rust metric (allocator tags, jobs, ...) as one JSON object. |
| `verdigris` `material_power` | Double-precision electrical solve for material-engineering power networks. |
| `vg-ffi` `allocator` | Tracking allocator: live/peak Rust heap overall and per `AllocTag`, with a thread-local tag scope (`allocator::tagged`); each block carries its tag in a small header so frees are charged correctly. |
| `vg-ffi` `allocator` | Tracking allocator that reports live Rust memory to the profiler. |
| `vg-gas` | The gas domain (M1b, `simulation.md` §4): `cell` (turf gas as an R6 `FieldKind`: exponential bulk-flow and diffusion kernels, reservoirs, reaction check in `local`, channels), `pipes` (pipes as an R7 `NetworkKind`, main-owned until M2), `world` (the gas world: main-owned mixtures, the field's `Sim`, the pipe network, gas handles, the heat exchange buffer, dirty observations, gas watches), `turf` (turf and SSair binds), `gate` (reaction and visibility data for frame threads). Numeric gas registry in `gas/ids.rs`. Reactions run in DM; see `code/ATMOSPHERICS/README.md`. `heat.rs` holds the heat domain's binds. |
| `vg-power` | The power domain (M3, `simulation.md` §6): `kind` (`Cables`, the R7 network kind: summary = supply, demand per APC channel, storage capacity; payload = pooled storage split by capacity), `geom` (the `get_connections()` rule, so Rust derives the graph from each piece's turf and directions), `apc` (the APC distributor), `smes` (SMES units) and `world` (`PowerWorld`: keys, batched edits, the ledger, one `step()` per machinery tick returning DM's events). Binds in `vg-ffi` (`ffi/src/power.rs`). |
| `vg-heat` | The heat domain (M4, `simulation.md` §7, `temperature.md`): `solid` (the turf solid heat field on R6's framework, with conduction, Stefan–Boltzmann radiation to space reservoirs and planet reservoirs), `body` (heat bodies created on first divergence, analytic relaxation on reservoirs, exact two-body steps otherwise, phase plateau, power, two couplings), `couple` (the `GasExchange` trait, the energy ledger, the solid ↔ turf gas task), `laws` and `world` (`HeatWorld`, the main-thread host with watches). The exchange math (pair exchange, phase plateau, relaxation, the regulator) is `vg_core::thermo`'s. Replaces `superconduct.rs`. |
| `vg-core` `grid` | `CellId` turf indices, `Dir` (BYOND directions and face sets), 16x16 copy-on-write chunked layers with per-chunk revisions, and the one `Grid` (block layers per `BlockKind`, z links, `step`). |
| `vg-core` `handle` / `arena` | 20-bit index + 4-bit generation handles (exact as f32); `Arena<T>` with 4096-slot chunks, stale-handle rejection, rayon iteration. |
| `vg-core` `bitset` / `intern` | Dense bitsets for dirty/active flags; string-to-numeric-ID interner. |
| `vg-core` `units` / `thermo` | SI newtypes (K, J, Pa, mol, W, J/K) and the one home of `TCMB`/`T0C`/`T20C`; the only exchange math: heat capacity, pairwise exchange (exact over a conductance and `dt`), the phase plateau, analytic relaxation and the regulator (`thermo::regulator`). |
| `vg-core` `rng` | Deterministic xoshiro256** streams per domain (`RngStreams` + `StreamId`), splittable. |
| `vg-core` `alloc` | `AllocTag`, the `AllocCounter` trait and lock-free `TagCounters` for the DLL's tracking allocator. |
| `vg-core` `cow` | `CowStore<T>`: chunked copy-on-write per-cell store (4096-slot linear or 16x16 spatial chunks); snapshots share unchanged chunks. |
| `vg-core` `owner` / `overlay` / `command` | R4 owners: a `Domain` has one worker-side writer (`DomainState`) and one DM-facing `MainPort` (sequenced command buffer, overlay of this tick's writes, the pinned `View`, scratch values). No locks on the DM path. |
| `vg-core` `jobs` | `JobRegistry`: named long jobs on their own small pool, below frame tasks (`JobCtx::checkpoint` parks while a frame runs), with progress, cancel, supersede keys and typed results (rust_core.md section 10). |
| `vg-core` `metrics` | `MetricsRegistry`: counters, gauges and histograms by name, lock-free to update, one JSON snapshot (section 11). |
| `vg-core` `recorder` / `replay` | `FlightRecorder` (ring of the last N frames' commands and metrics, dumped on a frame panic or on demand) and the `.vglog` codec: per-domain `Codec`s, `encode_log` / `decode_log`, `state_hashes`, `verify`. |
| `vg-core` `frame` / `sim` / `mailbox` | The frame task graph (declared reads/writes, levels run in parallel), the dedicated rayon frame pool, backpressure metrics, the flight recorder and `Sim::replay`, and `Mode::Fallback` (main-thread deltas within a budget, rust_core.md section 3.11). |
| `vg-core` `channel` | R5 channels: `channels!` declares a domain's typed, unit-tagged channels (scalar, vector, enum) with hysteresis and extractors; `validate_channels` checks them at boot; DM defines (`CH_<DOMAIN>_<NAME>`, `KPA(x)`). |
| `vg-core` `watch` | R5 watches: `Changed`, `Threshold`, `Band`, `Difference`, `ThresholdSet`, `Any`/`All`, checked at registration by `WatchPort` and evaluated in a per-domain frame task over changed chunks only (semantics table in the module docs). |
| `vg-core` `outbox` | R5 per-frame outbox next to each view: wakes, typed domain events and exact `Take` results; unread batches merge instead of being replaced; merge-by-key on overflow; flat fixed-stride DM encodings. |
| `vg-core` `timer` / `reactor` | R5 main side: hierarchical timer wheel (O(1) insert/cancel, tick precision), wake lanes (urgent/normal/background, merged per subscriber, once per lane per tick, budgeted), exact rate models (`Linear`, `Relax`, `Sum`) whose crossings go on the wheel, DM-owned keys. |
| `vg-core` `network` | R7 network framework: nodes/edges/regions in arenas, incremental merges and lockstep multi-source splits, conserving region payloads (`NetworkKind::split`/`merge`), batched commits, device edges between regions and cells, and `network::host` (frame task, `NetworkPort`, copy-on-write `NetworkView`, outbox events, region-channel mirror for watches). |
| `vg-core` `field` | R6 field framework: a `FieldKind` cells domain plus a `Geometry<K>` domain (capacity, blocked mask, reservoir flag), explicit chunk-parallel exchange with antisymmetric fluxes, stiffness sub-steps, active-chunk sleep/wake, a reservoir ledger; `field::kernel` (conduction, diffusion, pressure flow) and `field::toy` (reference heat and two-component gas). |

### R5 notes (for S1 and R6/R7)

- **Wiring.** `SimBuilder::add_watches(domain)` adds a domain's watch state and a `watch:<name>` task that runs after every other task; `declare_condition` registers rule templates. `build()` now returns `BuildError`, and fails with `BuildError::Boot` listing every bad channel table and declared condition.
- **Per tick (S1).** `sim.begin_tick()`, then `sim.drain(domain)` for each domain (stale wakes of removed watches and superseded `ThresholdSet` generations are already dropped), `reactor.ingest(out.wakes())`, `reactor.tick(now)`, and `reactor.drain(budget, &mut wakes)`. Bind sketches are in the `watch::WatchPort` and `reactor` module docs.
- **Semantics.** Watches see frame-end states, so a crossing undone within one frame never fires. Thresholds and set entries fire at the first evaluation if they already hold, and `Band` always reports its starting band. `Changed` never fires at registration.
- **Take conserves.** The worker records the exact value each `Take` removed in the outbox (`TakeResult`); DM's `take()` still returns the pinned value at once, and the difference is the transfer-out reconciliation (tested in `sim_toy.rs`).
- **Not recorded.** Watch registrations are not in the flight recorder. Views still replay bit for bit, because watches never write domain state, but replaying the outbox would need them.

### R7 notes (for M1b, M2 and M3)

- **Wiring.** `network::host::add_network::<K>(&mut builder, name)` returns the state resource and a `NetworkPort`. The port is not a sim port: S1 calls `port.commit()` before `dispatch_frame` and `port.refresh()` / `take_outbox()` after. Region channels: a task mirrors region scalars into a cell domain with `NetworkState::mirror` (cell = region slot), and ordinary watches run on it (`tests/network_sim.rs`).
- **Semantics.** A batch equals committing its removals, then its additions. A removed node's payload share is released at once (an outbox `TakeResult` keyed by node key). Merges keep the larger region's ID. Splits keep the parent ID for the side the search left open. Payload results are batch-order independent only for kinds that split proportionally on a positive weight.
- **Not recorded.** Network batches are not in the flight recorder yet. M3 needs a `Codec` for `Edit<K>` before power replays.
### R6 notes (for M1b and M4)

- **Wiring.** `field::add_field::<K>(&mut builder, dims, config)` registers the geometry domain, the cells domain `K` and a `field:<name>` task (after the apply tasks, before watches). DM (or boot) writes geometry with `put`/`GeomCmd` through `sim.port(key.geometry)`, and cells with `put`/`submit`/`take` through `sim.port(key.cells)`. `builder.add_watches(key.cells)` works as for any domain.
- **Physics contract.** `FieldKind::flux(a, b, dt)` is the a-to-b flux; the framework applies it once with each sign, sums a cell's fluxes before applying them, and adds reservoir inflow to `FieldState::ledger`. Kernels must clamp to the pair equilibrium and to `Side::share` of the donor (positivity when sub-steps are capped), and report `stiffness` so `n = ceil(dt * faces * stiffness)` sub-steps are monotone.
- **Sleep.** Commands, geometry changes and other tasks' writes wake chunks by CoW pointer diff; an edge into a sleeping chunk flows only once it is unsettled (so sleeping chunks are never written); a chunk sleeps when all its live edges are `settled` or the whole step left it `quiet` (the f32 fixed point).
- **Channels need capacity.** Extractors see only the cell, so a kind caches intensive values (temperature, pressure) in `refresh`, which runs on every touched cell after a step.
- **Precision.** Cells are f32: each step conserves to rounding (checked per step at 2e-6 relative), and long near-equilibrium runs random-walk at roughly 1e-8 relative per step.

### M3 notes (for S5, H4 and material power)

- **Wiring.** DM owns dense power keys (`power_key_alloc`). Cables send
  `POWER_OP_CABLE` (turf, `d1`, `d2`, the z-levels above/below for vertical
  pieces, an ender link id); power machines send `POWER_OP_MACHINE` and join
  every knot on their turf. Edits queue in `SSmachines.power_ops` and go in one
  `vg_power_edit()`; an explosion epoch holds them (`power_batch_begin/end`),
  so a blast is one commit. `vg_power_step()` runs once per machinery tick
  (the `SSMACHINES_POWERNETS` stage) and returns `POWER_EV_*` records: machine
  rebinds, region numbers, retirements, APC and SMES state, brownouts.
- **Ledger.** Per region and step: `avail` = registered supply
  (`set_power_supply`, persistent) + pulses (`add_avail`, one step) + SMES
  output offered; draws (`vg_power_draw`) never exceed `avail - load`. APCs run
  the distributor in key order, then SMES input shares the leftover by request,
  then SMES output pays what non-storage supply did not cover. Rust tests:
  conservation (property test over random edits, supplies, pulses and draws),
  exact SMES books, APC drain/brownout/restore/charge, idle silence.
- **Sleeping.** APCs and SMES never poll: Rust steps them and reports only
  shown changes (channels, charging, status, alarm, charge; SMES charge, I/O
  state). A DM-side change (UI, wires, cell swap, damage) resends the settings
  (`power_sync()`), directly or through one `process()` that returns
  `PROCESS_KILL`. DM's copies are current after every step, so a sync never
  loses Rust's progress. Trend counters that cycle on a settled APC
  (`longtermpower`, `chargecount`) are not reported.
- **Areas.** Static loads and one-offs are flushed per dirty area once per step.
  An APC channel change calls `area.power_change()` once; subscribed machines
  (not lights, which use the reactor key) re-check power and the base
  `power_change()` sends `COMSIG_MACHINERY_POWER_LOST`/`_RESTORED`.
- **Not built here.** Storage charge is stepped, not solved by rate-model
  crossings (a settled APC reports nothing, so DM cost is already zero); the TEG
  still computes its output in DM and registers it as a supply rate (the gas
  view/exchange buffer coupling waits for M1b); network batches are not in the
  flight recorder (no `Codec` for `Edit<Cables>` yet).

### M4 notes (for H1–H4, M1b and material science)

- **Frame.** `HeatWorld` owns its own `Sim` (two pool threads). A frame is
  `HEAT_DT` = 1 s: the field (conduction, radiation), the solid ↔ turf gas
  coupling, the bodies, the ledger mirror, then the watches. SSair's
  `process_turf_heat()` calls `vg_heat_tick(seconds)` (never waits; backlog is
  capped at two frames) and dispatches wakes. When S1 lands, the heat domains
  move into the one frame graph unchanged: they are ordinary `add_field` /
  `add_domain` / `add_task` registrations (`HeatWorld::new`).
- **Physics changes from superconduct.rs** (deliberate): bounds-checked
  neighbours (B1); space is a radiative reservoir (`ε σ A (T⁴ − T_sky⁴)`, sky at
  20 °C so a room-temperature hull is in balance) instead of conduction against
  a 7000 J/K vacuum above 20 °C only; no 303 K gate on turf ↔ gas coupling (cold
  air cools floors too; pairs within 0.5 K are left alone); the coupling uses the
  exact pair solution; planets (immutable non-space air) are reservoirs instead of
  being excluded; cross-z conduction stays blocked. Solid ↔ solid keeps today's
  law, `G = min(k_a, k_b) · harmonic(C_a, C_b)`, now integrated by the monotone
  sub-steps and conserving exactly (reservoir inflow in the ledger).
- **Energy books.** `HeatLedger` (a domain) holds cumulative flows no store
  kept: reservoirs, gas, released body baselines, power sources.
  `Totals::conserved()` is constant under the physics; tests check every
  coupling type with property tests.
- **Gas coupling.** Only through `GasExchange` (probe, exchange with a closure,
  changed turfs). Since M1b this is `world::HeatGas`, an exchange buffer over
  the gas field's views (see the M1b notes); nothing in vg-heat changed. The adapter never
  blocks a frame thread: every lock is a `try`, and a miss retries next frame.
- **Bodies for H2/H3/H4.** `Body` has capacity, a phase plateau, power (W), two
  couplings (solid cell, turf air, gas mixture by id, another body), a `KEEP`
  flag, and `flow` (J out through coupling 0 last step). Releases at
  equilibrium are host-driven (the worker reports, the host sends `Release`
  after anything DM queued), so heat DM adds never lands on a freed slot.
  Watches (`Threshold`, `Band`, `ThresholdSet`) work on bodies and cells; an
  analytic body schedules its settles at the exact crossing times of its
  watched levels (up to `BODY_LEVELS`).
- **Regulator (H4).** `regulator::Regulator::step(controlled, other, dt)`
  returns `work`, `moved` and `other` with `work = moved + other` exactly (B9,
  B10). H4 wires it to bodies (a machine body plus a gas mixture coupling) and
  publishes `work` to the power domain.
- **Not built here.** Heat-exchange pipe regions as a network kind (M3/H4); the
  per-zone clothing insulation chain (H2).
- **Constants (H1).** `consts.rs` entries marked `/// @dm-define` are the DM
  defines (T0C, BODYTEMP_NORMAL, HUMAN_HEAT_CAPACITY, the THERMAL_* defaults,
  …); DM must not redefine them (check_grep.sh). `vg_heat_constants()` returns
  the same values at runtime for `dq_heat_constants_match_rust`.

### M1b notes (for M2, M3, S2 and H4)

- **Ownership.** Every `/datum/gas_mixture` holds one gas handle (`world::MixRef`,
  in `_extools_pointer_gasmixture`): below `GAS_HANDLE_PIPE_BASE` a main-owned
  mixture (tanks, lungs, device buffers, scratch), then a pipe region, then from
  `GAS_HANDLE_TURF_BASE` a turf's field cell. `gas::with_mix` / `with_mix_mut`
  dispatch on it, so every DM gas bind works on every owner and the DM gas API
  did not change. The gas world is a main-thread thread local: no locks on the
  DM path.
- **Turf gas** is `cell::TurfGas` on `field::add_field`, in its own `Sim` (up to
  four pool threads). One SSair fire is one frame of 0.5 s: `vg_gas_tick()` pins
  the newest view, drains the outbox (events, `Take` results, watch wakes),
  applies heat, and dispatches the next frame without waiting. DM reads the
  pinned view plus the overlay; a DM write is one `GasCmd::Delta` with the
  absolute difference DM computed, so DM keeps exactly what it saw removed. A
  removal that races the worker clamps and counts the shortfall (`vg_gas_stats`).
  `GasWorld::take_turf` moves a whole cell out with a `Take`; the exact value
  arrives in the outbox and the difference is reconciled into the destination.
- **Flux.** Two exponential kernels, exact over any `dt` (so they never
  overshoot, whatever the sub-step): bulk flow toward pressure equality at
  `G (pa/na + pb/nb)`, carrying the upwind composition and energy per mole, and
  diffusion of each gas and the energy density. Against vacuum the bulk kernel is
  `n (1 - e^(-G p/n dt))`: decompression is the same law as every other gradient,
  and the stiffness gives up to 16 sub-steps for breach-scale gradients. Space is
  an immutable reservoir cell; planet cells are reservoirs DM may disturb, and a
  post-field task relaxes them back (25 % per frame). What flows into reservoirs
  is in the field's ledger (`vg_gas_totals`).
- **Events.** A `gas:post` task after the field emits `ReactionCheck` (the
  reaction requirements held in `local`), `VisualChange` (a changed visible-gas
  signature, or any DM-touched cell) and `PressureJump` (spacewind, the old
  `0.125 * dp > 5` rule). DM dispatches them in `SSair.process_gas_events`.
- **Adjacency** is the geometry domain: a DM air-block mask (with the z-level
  links) is one `GeomCmd::Blocked` per change, visible to DM's adjacency reads at
  once through the overlay. There are no topology barriers or transactions.
- **Pipes** are `pipes::Pipes` on a `Network` driven on the main thread
  (`PipeNet`): until M2 only DM devices move pipe gas, so pipe regions are
  main-owned (`rust_core.md` §3.1) and DM reads and writes them synchronously.
  `auxmos_pipenet_topology_batch` applies a DM batch, commits, and returns the
  regions DM rebuilds (region handle, member ports, prior regions, volume). A
  removed port's share is `Released` into the mixture DM named
  (`REMOVE_TO_MIXTURE`).
- **Watches.** Gas is reactor domain `REACT_DOMAIN_GAS`
  (`vg_ffi::reactor::ExternalDomain`): turf handles go to the field's watch port
  (evaluated in the frame), main-owned mixtures to a synchronous port evaluated
  at each reactor step. DM: `REACT_ON` / `REACT_WHEN` on `REACT_GAS(mixture)`
  with the `CH_GAS_*` channels. Pipe regions are not watchable until M2 moves
  them into the frame.
- **Heat.** `world::HeatGas` is the heat world's `GasExchange`: probes read the
  pinned gas views (and main-owned probes refreshed each gas tick), energy is
  queued and applied as gas commands at the next gas tick, and the `gas:post`
  task reports turf cells whose temperature moved. The heat world keeps its own
  `Sim` until S1 merges the frame graphs.
- **Test hook.** `vg_gas_run_frames(n)` (DM: `SSair.run_gas_frames(n)`) runs
  `n` frames to completion, one after another, and returns their events: atmos
  tests no longer wait on the wall clock.
- **Overlay or fallback.** Overlay. `DQ_GAS_FALLBACK=<budget cells>` builds the
  field in fallback mode for measurement. `tests::overlay_vs_fallback` (release,
  a 20x20 breached room, DM writing a sixth of the cells every tick, 200 ticks):
  overlay 74 us average / 191 us p99 main-thread time per tick and conserves
  (-0.007 mol drift on 72 mol added); fallback 1,281 us / 2,173 us, and because
  a rejected piece drops a chunk's half of a cross-chunk flux, it does not
  conserve (+254,689 mol drift). Overlay stays.
- **For M2.** Devices still move gas in DM (`process()`, `pump_gas_to`,
  `auxmos_batch_transfer`). M2 turns them into `Network` device edges: move
  `PipeNet` into the frame with `network::host::add_network`, give `Pipes` a
  `Command` (gas deltas) and an overlay for region payloads, and integrate device
  flows in a task between the pipe network and the gas field. Region channels
  then mirror into a cell domain for watches (R7 notes).
- **Left for M2/S2.** `machines.dm`'s gas subscribers still use the dirty
  observations (`watch_dirty_gas_mixture`, `drain_dirty_gas_observations`),
  which the gas world keeps: main and pipe writes are checked as they happen,
  watched turf cells once per gas tick against the pinned view. Moving them to
  gas watches is S2's.

## Building

```bash
# Linux (i686 — must match BYOND's 32-bit ABI)
bash verdigris/build-linux.sh

# Windows (cross-compile or native MSVC)
bash verdigris/build-windows.sh
```

Both scripts `cd` into the crate, run `cargo build --release --target i686-*`,
and copy the resulting `libverdigris.so` / `verdigris.dll` to the repo root
where DreamDaemon finds it.

### Toolchain

Pinned in `rust-toolchain.toml`: stable channel, with `rustfmt`, `clippy`, and
the two i686 targets. `rustup` reads this automatically — no manual setup
beyond installing rustup itself.

MSRV is 1.85 (edition 2024).

### Binaries

`libverdigris.so` and `verdigris.dll` are build outputs and are gitignored.
`bin/build.cmd` and `tools/build/build.sh` build them, and CI builds them from
source.

### Tests

```bash
cd verdigris
cargo fmt --all --check
cargo test                                            # host crates, in parallel
cargo test --target i686-pc-windows-msvc -p vg-gas    # gas (or i686-unknown-linux-gnu)
cargo bench -p vg-bench                               # criterion benchmarks
cargo run -p vg-replay -- verify <log.vglog>          # replay a flight-recorder log
```

A plain `cargo test` builds the default members (`vg-core`, `vg-layout`,
`verdigris`, `vg-bench`) for the host. `vg-gas`, `vg-ffi` and `auxcallback`
depend on byondapi, which is 32-bit only, so they build and test on the i686
targets only.

## The rules

These exist because their absence will crash the server in production.

### Rule 1 — Declare every bind with `#[auxmacros::bind]`

```rust
/// Doc comment; copied into the generated DM binding.
#[auxmacros::bind("/proc/foo")]
fn foo(x: ByondValue) -> eyre::Result<ByondValue> {
    // body
}
```

DM then calls `vg_foo(x)`. A Rust panic unwinding across the BYOND FFI boundary
is undefined behaviour and crashes DreamDaemon with no DM-side stack. The macro
wraps the body in `catch_unwind`, turns a panic into an error that surfaces as a
DM runtime, and prefixes every error with the bind's name. The bound function
must return `eyre::Result<ByondValue>`. Variadic binds use
`#[auxmacros::bind_raw_args]` (DM: `vg_foo(...)`). Never use `byondapi::bind`
directly: the generator only sees `auxmacros` binds.

After adding, removing or changing the arguments of a bind, run
`tools/build/build.sh verdigris-bindings` and commit `_bindings.dm` and
`ffi/src/abi.rs`. The two share an ABI hash; `verdigris_init(VERDIGRIS_ABI)`
stops the boot when the DLL and the DM build disagree.

Integer constants DM needs (bit masks, strides, flags) are exported the same
way: put `/// @dm-define DM_NAME` on a `pub const NAME: <int> = <literal>;` and
the generator emits `#define DM_NAME <literal>`.

### Rule 2 — No strings in hot paths

Every FFI call costs microseconds (byondapi marshalling). String allocations
across the boundary compound that:

- Gas IDs are numbers, never strings: fixed `GAS_ID_*` constants from `gas/ids.rs`.
- Turf handles are `usize` arena indices, never datum paths.
- Lists returned to DM should be `Vec<f32>` / `Vec<i32>`, not `Vec<String>`.

### Rule 3 — Cross the boundary once per batch, not once per element

DM is the loop owner; Rust is the work unit. The pattern is:

- DM gathers a batch (e.g. "these are the 47 active turfs this tick"),
- one FFI call passes the batch to Rust,
- Rust does the heavy lifting (possibly with `rayon`),
- one FFI call returns aggregate results (or queues callbacks for later drain).

Never loop in DM calling a Rust per-tile getter inside.

### Rule 4 — Destroy() discipline

Every DM datum that holds an arena handle (gas mixtures, material power
graphs) must release it on `Destroy()`.

### Rule 5 — Single-threaded BYOND, multi-threaded Rust

The BYOND VM is single-threaded. `rayon` is fine *inside* Rust between FFI
calls. **Never** hold a `ByondValue`, call into DM, or read DM state from a
worker thread. The pattern for "Rust needs DM to do something" is a callback
queue that DM drains on the main thread (see `auxcallback::byond_callback_sender`).

## CI

- `run_integration_tests.yml` builds verdigris from source on every PR
  (`bash verdigris/build-linux.sh`), with a Swatinem rust-cache.
- `run_linters.yml` runs `cargo fmt --check`, `cargo clippy -D warnings`, and
  `cargo test`.

## Build-info

`ffi/build.rs` invokes [`bosion`](https://crates.io/crates/bosion) to capture the
git short-hash at build time; `verdigris_version()` returns `verdigris v0.1.0
(abc1234)` which DM can compare against an expected pin if needed.
