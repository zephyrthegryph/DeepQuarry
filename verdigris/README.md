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
├── core/                   <- vg-core: domain-agnostic primitives (grid, ...).
│                              Host-buildable, no byondapi, no global statics.
├── domains/
│   ├── gas/                <- vg-gas: vendored auxmos (gas arena, turf diffusion,
│   │                          heat); i686 only until its binds move to vg-ffi.
│   │                          See domains/gas/UPSTREAM.md.
│   └── layout/             <- vg-layout: station layout planner, cave generator,
│                              and the offline station-layout tools (src/bin/)
├── ffi/                    <- vg-ffi: BYOND binds (lifecycle, layout, cave gen)
│   │                          and the tracking allocator; i686 only
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
| `vg-ffi` `lifecycle` | `verdigris_init`, `cleanup`, version/feature metadata, allocator diagnostics. |
| `vg-layout` `random_map` | Cellular-automata cave generator used by expedition sites. |
| `vg-layout` `station_layout` | Generated-station layout planner; planning runs as a `vg-core` job (`plan_catalog_job`). |
| `vg-ffi` `jobs` | The DLL's job registry and the generic job binds (`verdigris_job_poll` / `_progress` / `_cancel` / `_finish`, `verdigris_jobs_completed`). |
| `vg-ffi` `metrics` | The DLL's metrics registry and `verdigris_metrics()`, which returns every Rust metric (allocator tags, jobs, ...) as one JSON object. |
| `verdigris` `material_power` | Double-precision electrical solve for material-engineering power networks. |
| `vg-ffi` `allocator` | Tracking allocator: live/peak Rust heap overall and per `AllocTag`, with a thread-local tag scope (`allocator::tagged`); each block carries its tag in a small header so frees are charged correctly. |
| `vg-gas` | Gas arena, turf diffusion, decompression and heat conduction. Reactions stay in DM; see `code/ATMOSPHERICS/README.md`. |
| `vg-core` `grid` | Bounds-checked turf-index neighbour arithmetic, 16x16 chunked layers, per-kind blocked-direction layers (`Grid`). |
| `vg-core` `handle` / `arena` | 20-bit index + 4-bit generation handles (exact as f32); `Arena<T>` with 4096-slot chunks, stale-handle rejection, rayon iteration. |
| `vg-core` `bitset` / `intern` | Dense bitsets for dirty/active flags; string-to-numeric-ID interner. |
| `vg-core` `units` / `thermo` | SI newtypes (K, J, Pa, mol, W, J/K); heat capacity, energy/temperature, energy-conserving pairwise exchange. |
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

- Gas IDs are `u8`, never strings, after one-time registration at boot.
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
