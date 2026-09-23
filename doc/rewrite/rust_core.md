# Rust core (track R)

`vg-core` is the shared base that every simulation is built on. It owns everything that isn't physics, and a domain supplies only its data and its physics:
- identity and storage;
- the grid;
- threading;
- change tracking;
- scheduling;
- the bridge to DM;
- jobs;
- metrics;
- testing.

## 1. Where we start

Verdigris already has most of these pieces, but they are written for gas only.

| Existing piece | Where |
|---|---|
| Arena of mixtures with a free list, per-slot revisions and bounded 4096-slot growth | `atmos/src/gas.rs:110-134` |
| Change signatures with hysteresis baselines (0.5 kPa, 0.5 K, 0.01 mol), interest masks, merged dirty masks, and drains of either `[id, mask]` pairs or 15-value observation records | `gas.rs:157-647`, `lib.rs:210-278` |
| Optimistic transactions: snapshot, solve on a worker, publish each connected piece, reject a piece if DM changed it | `gas.rs:31-98, 433-508` |
| Generational cell handles, and adjacency by coordinate arithmetic | `turfs.rs:90-125, 1576-1637` |
| Active-set scheduler with urgent/fresh/frontier lanes, epoch exclusion and an adaptive budget (128–4096 seed cells) | `turfs.rs:455-603, 893` |
| Topology generations, transaction versus batch modes, and a `TASKS` barrier | `turfs.rs:721-833` |
| Incremental pipe topology: dirty ports and regions, re-flooding only touched components, stable region IDs, mass-conserving recipes | `pipenets.rs` |
| Callback queue to the main thread | `crates/auxcallback` |
| Panic-safe bind macro | `crates/auxmacros` |
| Global allocation tracking | `verdigris/src/allocator.rs` |
| Submit/poll job registries | `material_power.rs`, `station_layout/ffi.rs:26-93` |

It also has problems the core must not repeat:
- **Locking on the DM path.** Every DM gas write takes four locks and makes two allocations, and it blocks while a solver transaction is running.
- **Global statics everywhere.** Tests need the i686 target and a single test thread.
- **Workers pinned to rayon's pool.** They are endless loops that permanently occupy threads in rayon's global pool.
- **Unsafe identifiers.** Gas slots have no generation, so a recycled slot can be mistaken for the old mixture. Numbers cross to DM as 32-bit floats, so revision counters stop being exact past 2^24.
- **One boxed closure per event.** Pressure events send one per cell.
- **Duplicate graphs.** Turf adjacency is a general-purpose graph that stores every edge twice, plus three hash maps. Heat keeps a second, separate graph, and its neighbour arithmetic has no bounds check (bug B1).

## 2. Crates

```
verdigris/
  core/       vg-core      domain-agnostic; host-buildable; no byondapi; no global statics
  domains/
    gas/      vg-gas       gas registry, mixture maths, flux, reactions
    devices/  vg-devices   atmos devices as network edges
    power/    vg-power     power ledger, storage rate models
    heat/     vg-heat      heat field and heat bodies
    layout/   vg-layout    station layout, cave generation, generation planners
  ffi/        vg-ffi       the only crate that uses byondapi (i686); every bind; DM binding generator
  verdigris/  verdigris    the DLL; owns one World; links everything
  tools/                   criterion benchmarks, replay tool, snapshot fixtures
```

`material_power.rs` belongs to the body rewrite's session. It moves onto `core::jobs` and the power domain only with their agreement.

## 3. Owners, frames and threads

### 3.1 Owners

Every entity has exactly one owner at a time, and only its owner writes it:
- **Grid cells** are owned by their domain's worker: turf gas, turf heat.
- **Network regions** are owned by the network domain's worker: pipe regions, power nets.
- **Main-owned entities** are ones DM changes and the simulation rarely touches: tanks, a mob's lungs, scratch mixtures. DM reads and writes them synchronously, with no staleness.
- **Transfers:** ownership moves by command. When a canister connects to a pipe network, its mixture moves to the pipe worker; when it disconnects, the mixture moves back to the main thread.

There are no locks anywhere on the DM path.

### 3.2 Commands

DM writes to worker-owned entities are commands, appended to a sequence-numbered buffer. Appending takes constant time and needs no locks. At each frame boundary the buffer is swapped out and handed to the worker, which applies all its commands before simulating.

Commands carry **absolute amounts computed on the main thread**, not ratios: "remove these moles and this much energy from cell X", "add these moles and this energy". So:
- DM keeps the result it computed. `remove_air` returns exactly what DM saw removed.
- Mass and energy are conserved when the worker applies the command.

### 3.3 Views

After each frame the worker publishes an immutable **view** of its state.
- **Chunked copy-on-write.** State lives in fixed-size chunks: spatial 16×16 chunks for grid fields, and 4096-slot chunks for arenas. A new view shares every chunk that didn't change and copies only the ones that did, so the extra memory scales with the amount of change. A chunk is freed when no view holds it any more.
- **Versioned.** Each view carries its version and `applied_through`, the last command number it includes.
- **Pinned per tick.** At the start of each tick the main thread pins the newest view, and every DM read that tick goes to it. Reads take no locks and cost a pointer chase, and DM sees one consistent world for the whole tick.

### 3.4 The overlay

DM expects to read its own writes immediately. The main thread therefore keeps an **overlay** of worker-owned entities it has written that no published view includes yet.
- The first write to an entity copies its value from the pinned view into the overlay. Later reads and writes that tick go to the overlay.
- Once a pinned view's `applied_through` reaches an overlay entry's sequence number, that entry is dropped.
- The overlay belongs to the main thread, so all DM code sees every DM write straight away.

### 3.5 Scratch values

A mixture removed in order to be inspected, reacted, breathed or merged somewhere else is a **scratch value** on the main thread. It never gets an arena slot and never reaches a worker, unless DM keeps it past the end of the tick; in that case it becomes a main-owned entity. `assume_air(scratch)` turns into a single command.

In the profiled round, the remove-then-merge pattern created 1.5M DM gas mixtures, each with a Rust slot. Scratch values make those free on the simulation side.

### 3.6 Frames and the task graph

A frame is one simulation step. It runs as a small task graph:
1. Each task declares what it reads and writes.
2. The executor runs independent tasks in parallel and dependent ones in order.

A typical frame looks like this:

```
apply commands (per domain, in parallel)
  → devices (write pipe and turf gas; read power state)
  → gas field (write gas; read the heat coupling from the exchange buffer)
  → heat field and bodies (read gas temperature)
  → power settlement (read device demand)
  → watches (per domain, in parallel)
  → publish views and outboxes
```

- **Coupling between domains.** Coupled domains read each other's values from the previous frame through **exchange buffers**. A flux between two domains, such as solid-to-gas heat, is computed once and applied to both sides, so energy is conserved.
- **Different rates.** Gas runs at SSair's cadence (0.5 s, speeding up under pressure urgency). Slower domains sub-step or skip frames, but coupled pairs always share a time step.
- **Long jobs** (§10) run below frame tasks in priority, so they never delay a frame.

### 3.7 Threads

- **Pool.** A dedicated rayon `ThreadPool`, sized to leave cores for BYOND's own threads. There are no endless loops parked on pool threads.
- **Scheduling.** The frame executor runs on that pool: domain tasks use `join`/`scope`, and each task parallelizes by chunk inside.
- **Main thread.** The main thread never runs simulation.

### 3.8 Backpressure

DM never waits for a worker.
- If a frame runs long, commands keep queuing and the next frame applies them all.
- Views simply lag behind.
- Metrics report frame duration, command backlog and view age.
- If view age exceeds a budget, the benchmarks flag it.

### 3.9 Determinism and replay

- Commands are applied in sequence order.
- Chunk-parallel sums are combined in a fixed chunk order.
- Floating-point work never depends on thread timing.

Replaying a recorded command log (§11) therefore reproduces the same views bit for bit. The flight recorder, the replay tool and the conservation tests all rely on this.

### 3.10 The one inexact case

A worker-owned entity DM writes can be at most one frame out of date in DM's view. Relative commands make that harmless in every case but one: a DM removal that races a simulation drain of the same cell below the amount requested.
- The worker clamps the removal at zero and counts the shortfall in metrics.
- Anything that needs exact synchronous behaviour stays main-owned (§3.1).

### 3.11 Fallback

If the overlay proves too complex in practice, the fallback is the model from the first draft:
- the main thread owns live state;
- workers return deltas;
- the main thread applies them within a budget, one connected piece at a time, rejecting pieces DM changed since the snapshot.

It is simpler, but main-thread cost grows with the number of changed cells and spikes during decompression. M1 decides between the two with measurements.

## 4. Identity

- **Handles.** `Handle<T>` is an index plus a generation. It crosses to DM as one number that is exact as a 32-bit float: a 20-bit index and a 4-bit generation. A stale handle is rejected with an error instead of quietly aliasing a recycled slot. Debug and CI builds also check the owning DM object.
- **Revisions stay in Rust.** DM receives events, not counters, so the 2^24 precision limit no longer matters.
- **Registries have numeric IDs.** Gases, materials, channels, event kinds, units and network kinds get numeric IDs that are generated into DM defines. No strings cross on hot paths; today every gas call sends an interpolated gas ID.

## 5. Stores

- **`Arena<T>`**
  - Generational slots and a free list.
  - Grows in fixed 4096-slot chunks (never geometrically).
  - Can lay out hot fields as separate columns (`#[derive(Columns)]`).
  - Tracks bytes per arena under an allocator tag.
- **`Grid`**, one per z-level, divided into 16×16 chunks:
  - **Addressing:** a cell is addressed by coordinates, and its neighbours by bounds-checked arithmetic.
  - **Block layers:** per-cell blocked-direction bitmasks, one layer per kind — air, heat, movement, opacity and radiation shielding.
  - **Extra links:** a sparse table for links the grid doesn't express, such as multi-z connections, shuttles and portals.
  - **Unallocated chunks:** chunks that are pure space or unused are never allocated.
  - **Domain columns:** domains attach their per-cell data as sparse or dense columns keyed by cell.
  - **What it replaces:** the petgraph `StableDiGraph` with every edge stored twice, `TurfGraphMap`, the generations map, `MIX_TO_TURF`, and heat's separate `TURF_HEAT` graph.
- **Sets:** dense bitsets for dirty and active flags, sparse sets for sparse domains, and a small string interner.
- **Memory policy.** The library shares BYOND's 32-bit address space, which peaks at 2.35 GB today.
  - Indices are u32 and values f32.
  - Nothing grows geometrically.
  - Each domain has a memory budget, reported to the benchmarks.
  - Allocations carry a domain tag (§11).

## 6. Channels and watches

### 6.1 Declaring channels

Each domain declares its channels in one macro:

```rust
channels! { Gas {
    PRESSURE:    Scalar<Kpa>    hysteresis 0.5,
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.5,
    COMPOSITION: Vector<Moles>  hysteresis 0.01,
}}
```

- Each channel declares its value type (scalar, vector or enum), unit, hysteresis and extractor.
- Code generation produces numeric DM defines, with unit tags (`CH_GAS_PRESSURE`, `KPA(x)`).
- Baselines are kept only for entities that someone watches. Today every mixture that changes gets one.

### 6.2 Watch kinds

| Kind | Fires when | Used by |
|---|---|---|
| `Changed(mask)` | Any listed channel moves past its hysteresis | Today's gas subscriptions |
| `Threshold(ch, op, value)` | The value crosses a limit (edge-triggered, with hysteresis) | Melting, ignition, overpressure |
| `Band(ch, [levels])` | The value moves into a different band | Air alarm levels |
| `Difference(a, b, ch, value)` | The difference between two entities crosses a limit | Firedoors: pressure or temperature across the door |
| `ThresholdSet(ch)` | Any of many thresholds on one entity is crossed. Each threshold carries a payload with a generation, and adding or removing one is cheap. | A container's latent contents, a mob's comfort bands, a reagent holder's reaction temperatures, phase changes |
| Combinations | AND/OR of the above | Air alarms watching several gases |

### 6.3 Checking

- DM builds conditions with generated constructors whose constants carry units, e.g. `ABOVE(handle, CH_GAS_PRESSURE, KPA(5000))`.
- **At registration**, Rust checks that the channel exists for that kind of entity, that types and units match, and that hysteresis is sane. A failure raises a DM runtime with context.
- **At boot**, every declared rule is validated once, because rules are declared per type ([rules.md](rules.md)). A mistake fails the boot test instead of surfacing in play.

### 6.4 Where watches run

Domain watches are evaluated inside the frame (§3.6), next to their data, and only for entities whose channels changed. Their results go to the outbox. A stale payload, such as a threshold group the ledger has since removed, is recognized by its generation and ignored.

## 7. The main-side reactor

These pieces live on the main thread, in Rust structures that only the main thread touches, so they need no locks:
- **Timer wheel.** A hierarchical wheel at tick resolution.
  - Inserting and cancelling take constant time, and no DM datum is created per timer.
  - A timer fires at tick precision; an airlock timer never waits for a 0.5 s simulation frame.
- **Wake lanes.** Urgent, normal and background. Each subscriber appears once per lane, with its reasons merged, and the lanes drain within SSreactor's budget ([reactor.md](reactor.md)).
- **Rate models** for main-owned and DM-owned quantities. Domain-owned rate models live in their domain.

  | Model | Value at time t |
  |---|---|
  | `Linear { v0, rate, t0, clamp }` | `clamp(v0 + rate·(t − t0))` |
  | `Relax { target, v0, k, t0 }` | `target + (v0 − target)·e^(−k·(t − t0))` |
  | `Sum` | A sum of linear terms (a store with inflow and outflow) |

  - **Reading** a model evaluates it at the current time.
  - **Crossing times** are solved exactly and scheduled on the wheel.
  - **Input changes:** when an input changes, the model restarts from the current value and re-schedules.
- **DM-owned keys.** State that only DM changes, such as door modes and area alarms, is published by key. Publications are batched per tick and dispatched to subscribers on the main thread.

## 8. Events out, commands and reads in

- **Outbox.** Typed records in preallocated ring buffers, one per kind:
  - Wake, PressureJump, ReactionCheck, VisualChange;
  - Ignite, Melt, ThresholdCrossed;
  - Brownout, Restore, TopologyChanged, Destroyed.

  DM drains each kind in one call per tick as a flat numeric list with a fixed stride per kind. If a buffer overflows, records are merged by key rather than dropped. This replaces auxcallback's boxed closure per event.
- **Commands.** Typed and sequence-numbered. Bulk commands (registration, topology edits, device settings) are packed numeric lists; today pipe operations are text such as `"op,a,b,vol;"`.
- **Batched reads.** One call returns pressure, temperature, volume, total moles and composition. Today `get_gases` alone makes N+1 calls, plus a `text2path` per gas.
- **No temporary mixtures.** `transfer_ratio(src, dst, ratio)` and similar calls replace remove-then-merge, alongside scratch values (§3.5).

## 9. The DM bridge

- **One bind macro.** Every bind is panic-safe (as today), decodes typed arguments, adds error context, and counts its own calls and time.
- **Generated `code/__defines/verdigris/_bindings.dm`:**

  ```dm
  /proc/vg_gas_read(handle)
  	var/static/__f = load_ext(VERDIGRIS, "byond:vg_gas_read_ffi")
  	return call_ext(__f)(handle)
  ```

  It also holds the numeric defines (gas IDs, channels, event kinds, units) and doc comments. Today no call caches its `load_ext` handle, and `VERDIGRIS_CALL` rebuilds its name string on every call.
- **CI** regenerates the file and fails if it differs from the committed copy. The existing `generate_binds` test is the starting point.
- **Version handshake.** `verdigris_init()` compares the library's ABI version with a generated DM constant and stops the boot on a mismatch.
- **Migration.** All 98 hand-written `call_ext` sites and the `VERDIGRIS_CALL` wrappers move onto the generated procs, and the hand-written routes are deleted (`gas_mixture.dm`, `dq_linda_turf_air.dm`, `auxmos_init_bridge.dm`, `rust_pipenets.dm`, `material_power_graph.dm`).

## 10. Jobs

One registry handles long work, with submit, poll and cancel:
- station layout;
- generation planners;
- material power (with its owner);
- batches of path searches.

Each job has a generation tag, so a cancelled or superseded result is dropped, and results arrive through the outbox. Jobs run below frame tasks in priority.

## 11. Metrics, memory tags, flight recorder

- **Metrics registry.** Counters, gauges and histograms per domain:
  - frame time and view age;
  - command backlog;
  - active cells and wakes;
  - per-bind calls and time.

  SSprofiler and the benchmark `mark()` pull them all in one call, replacing the roughly 40 telemetry var writes per atmos generation.
- **Allocator tags.** Current and peak bytes per domain. Today there is only a global total.
- **Flight recorder.** In development builds, a ring buffer of commands and frame boundaries. The replay tool reruns it offline, for bug reports and for benchmarks built from real rounds.

## 12. Testing

- **Where tests run.** Every crate except `vg-ffi` builds and tests on x86_64, in parallel, with no global state.
- **Property tests:**
  - mass, energy and charge are conserved through any sequence of commands and frames;
  - a stale handle is always rejected;
  - watches fire exactly once per crossing;
  - network split and merge conserve their payload, and incremental updates equal a full rebuild;
  - timers fire in order;
  - the overlay matches a synchronous reference model.
- **Reference solutions** for heat conduction and two-body exchange.
- **Criterion benchmarks** on world snapshots exported by the `boot_memory` scenario: the gas step, the heat step, a network commit, and command application.
- **Replay determinism.** A recorded session replays to identical views.

## 13. What moves out of today's code

| Existing | ≈ lines | Becomes |
|---|---|---|
| Arena, free list, revisions, bounded growth (`gas.rs`) | 150 | `core::arena` |
| Signatures, baselines, interest masks, dirty drain (`gas.rs`) | 300 | `core::watch` |
| Snapshot and per-piece publication (`gas.rs`), topology transactions (`turfs.rs`) | 450 | `core::frame` (views and apply) |
| Cell handles, neighbour arithmetic, turf map (`turfs.rs`) | 350 | `core::grid` (rewritten dense; B1 fixed) |
| Urgent/fresh/frontier lanes (`turfs.rs`) | 150 | `core::field` active sets |
| `PipeTopology` (`pipenets.rs`) | 450 | `core::net` |
| Heat share formulas, loss to space (`superconduct.rs`) | 150 | `core::thermo` |
| Worker loop, adaptive budget, telemetry (`processing.rs`) | 400 | `core::frame`, `core::metrics` |
| auxcallback, auxmacros, allocator | 310 | `core::outbox`, `vg-ffi`, `core::metrics` |
| Job registries | 150 | `core::jobs` |

- **Moves:** about 2,900 lines, roughly a third of the atmos code.
- **Deleted:** about 1,500 dead lines (fixes.md DEAD1).
- **What gas keeps:** about 2,000–2,500 lines once it sits on the field framework ([simulation.md](simulation.md)), down from about 9,000 today.

## 14. Panic/unsafe/architecture audit (rewrite/rustaudit, 2026-09)

A full-workspace pass auditing panic safety, `unsafe`, cross-domain
duplication and lint cleanliness. Everything below is landed on
`rewrite/rustaudit` unless marked "not done".

### 14.1 Panic safety

- **Every FFI entry point already never unwinds into BYOND.** Both
  `#[auxmacros::bind]` and `#[auxmacros::bind_raw_args]` wrap the function
  body in `catch_unwind` and convert a panic into an `eyre::Result::Err`
  (surfaced to DM through `/proc/byondapi_stack_trace`), with the bind's
  name as context. This predates the audit; what changed is *where* the
  logic lives: it's extracted out of the proc-macro's codegen into a plain,
  unit-tested function, `auxcallback::panic_guard::run_guarded`
  (`ffi/callback/src/panic_guard.rs`), so the property ("a panicking bind
  body returns `Err`, not a crash") has real `#[test]`s instead of only
  being exercisable through a BYOND-hosted DLL. The macro itself is now a
  two-line wrapper around that call.
- **`.unwrap()`/`.expect()` audit.** Counted with test files and `#[cfg(test)]`
  modules excluded: ~134 in non-test production code (well under the ~282
  figure, which counts test code too). The large majority — `core/src/arena.rs`,
  `core/src/network/graph.rs`, `core/src/frame.rs`, etc. — are already
  `.expect("invariant: ...")` with the invariant stated inline (e.g. "node's
  region is live", "checked len() >= 2 above"); these are correct as-is per
  the "keep true invariants with a message" rule and were mostly left
  alone. The ~20 *bare* `.unwrap()`s in production code (no message) were
  the real audit target:
  - `domains/gas/src/gas/types.rs`: `get_reaction_info()` (reads
    `SSair.gas_reactions`), `GasType::new`'s `fire_products` parsing,
    `gas_visibility(idx)`'s out-of-range index, `destroy_gas_info_structs`
    called before init, and `update_gas_refs`'s `GasRef::update` — all now
    return/propagate `Result` or degrade gracefully instead of panicking on
    malformed or out-of-order DM state.
  - `domains/layout/src/station_layout/structural.rs`: coordinate `i16`
    conversions now fall back instead of panicking; two bipartite-matching
    `unwrap()`s guarded by `||` short-circuit and a boundary-search
    `unwrap()` guarded by a `len() >= 2` check are now `.expect("invariant: ...")`.
  - `verdigris/src/material_power.rs` (1 unwrap): **not touched** — owned by
    DQ Medical per the worktree's constraints; report only.
  - Everything under `domains/heat`, `domains/power`, `core` (outside the
    files above) either had zero bare unwraps or was already invariant-
    documented; not modified.
- **Stale/garbage handle safety.** `core::arena::Arena` already rejects a
  stale or out-of-range handle via `ArenaError::{Stale,OutOfRange}` — no
  `.unwrap()` on a handle lookup anywhere in the arena itself. This is the
  one arena/handle abstraction in the tree; `vg-gas`'s own cell/pipe
  indices are plain array indices bounds-checked at the FFI boundary, not
  a second generational-handle system (no duplication to fix here).

### 14.2 `unsafe` audit (all 24 occurrences)

| Site | Verdict |
|---|---|
| `core/src/mailbox.rs` (`Send`/`Sync` impls, 2x `Box::from_raw`) | Already had `// SAFETY:` comments proving soundness. Untouched. |
| `domains/gas/src/gas/mixture.rs`: `set_moles`/`adjust_moles`/`adjust_multi` (3x `get_unchecked_mut`) | Sound (bounds guaranteed by a preceding `maybe_expand`), but undocumented. Added `// SAFETY:` comments. |
| `domains/gas/src/gas/mixture.rs`: `vis_hash`/`vis_hash_changed` (`get_unchecked` over a caller-supplied slice with no length invariant enforced at the call site) | **Unsound as written** (a shorter `gas_visibility` slice than `self.moles` would be OOB) and, on inspection, **dead code** — neither function has any caller anywhere in the tree. Deleted, along with the now-orphaned `visibility_step` helper. |
| `ffi/macros/src/lib.rs` (SIMD dispatch `unsafe fn`/call, feature-detected) | Already commented, standard sound pattern. Untouched. |
| `ffi/src/allocator.rs`: `TrackingAllocator`'s `unsafe impl GlobalAlloc` (8 blocks: `finish`, `alloc`, `alloc_zeroed`, `dealloc`, `realloc`) | Sound but had zero `SAFETY` comments despite real header-prefixed-block pointer arithmetic across threads (it's the process's global allocator, so every thread, including rayon jobs, calls it). Documented every block: why `outer()`'s overflow check bounds `base.add()`, why `finish`'s write is in bounds, and why `dealloc`/`realloc`'s `Layout::from_size_align_unchecked` reconstructs exactly the padded layout `alloc`/`alloc_zeroed` originally requested. |

No raw pointers cross threads outside the allocator (which is inherently
process-global) and `Latest<T>`'s mailbox (already sound/documented); no
`Send`/`Sync` impl needed a second look.

### 14.3 Architecture / duplication

- **Bind panic/error plumbing**: consolidated (14.1) — this was the one
  real duplication risk (each bind site re-deriving catch/wrap logic); now
  one function.
- **Gas heat.rs vs vg-heat**: already correctly factored. `domains/gas/src/heat.rs`
  is FFI marshalling and a thread-local `HeatWorld` owner only; every actual
  heat-transfer formula lives in `vg-heat` (`domains/heat/`), imported as a
  library. No duplicated physics found here — the task's suspicion
  predates the M4 heat-domain landing, which already did this split.
- **Gas cell.rs `revision`/band tracking vs `core::watch`**: **found, not
  merged.** `domains/gas/src/cell.rs`'s `GasCell::band_check` (pressure/
  temperature/mole-count dirty bands, bumping a `revision` counter DM polls)
  is conceptually the same idea as `core::watch`'s generic `Band`/`Threshold`
  conditions, but `vg-gas` predates `core` (it's the vendored-auxmos, i686-
  only, hot-path gas arena) and was never migrated onto `core`'s
  chunk/channel/frame model. Rewriting `GasCell` onto `core::watch` is a
  real simplification opportunity but is a hot-path behavioral rewrite of
  the atmos frame loop, risky to land unverified in the same pass as a
  "must not change behavior" audit, and gas is explicitly out of strict-
  lint scope pending its own migration (see `domains/gas/UPSTREAM.md`).
  Left as a documented follow-up, not attempted.
- **Crate dependency direction**: checked with `cargo tree`-equivalent
  reasoning from each `Cargo.toml`. Holds: `core` depends on nothing in the
  tree (host-buildable, no byondapi); `domains/{gas,heat,layout,power}` each
  depend only on `core` (+ `auxcallback`/`auxmacros`/byondapi for gas's FFI
  binds) and never on each other; `ffi` depends on the domains and `core`;
  `verdigris` (the DLL) depends on `ffi` + `vg-gas` (+ `auxmacros`/
  `auxcallback`, added this pass — see 14.4). No domain-to-domain edges
  found.
- **Handle/arena wrappers, network/topology, unit conversions, rate models,
  stats/metrics plumbing**: single implementations each (`core::arena`,
  `core/src/network/graph.rs`, `vg_heat::consts`, `core::metrics`); no
  second copy found in a domain crate.
- **`domains/layout` dead code**: ~50 `dead_code` warnings, all confirmed
  by rustc as genuinely unreachable private functions in
  `station_layout/{structural,content}.rs` (an earlier layout-generation
  approach superseded by the current seeded/content-aware pipeline, never
  deleted). **Not removed this pass** — safely deleting ~40 functions
  across two ~9,000-line files by hand risks brace/import mistakes without
  much more budget than this audit had left; left as a clearly-flagged
  follow-up (see 14.5) rather than attempted half-carefully.
- **`content.rs` rotation-retry bug**: while chasing a `clippy::never_loop`
  error, found that the fixture-placement search's inner `for turn_offset
  in 0..4` loop can never advance past `turn_offset == 0` (every exit path
  is a `continue`/`break` on the *outer* loop's label). Only the first of 4
  candidate rotations is ever tried per anchor. Left behaviorally identical
  (rewritten as an honest single-pass block, not a loop) and flagged as a
  follow-up task, since actually trying all 4 rotations changes generated
  station layouts.

### 14.4 Mechanical changes forced by moved APIs

- `verdigris/Cargo.toml` gained an `auxcallback` dependency (material_power.rs
  uses `#[auxmacros::bind]`, which now expands to a call into
  `auxcallback::panic_guard::run_guarded`). No change to `material_power.rs`
  itself.
- `ffi/Cargo.toml` gained the same `auxcallback` dependency, for the same
  reason (its many `#[bind]`s).

### 14.5 clippy

`cargo clippy --workspace --target i686-pc-windows-msvc` (default features):
- 4 pre-existing hard errors (deny-by-default correctness lints) fixed:
  two `clippy::never_loop` (one dead/unreachable check deleted, one loop
  rewritten to remove-then-error instead of return-on-first-iteration, one
  turned into an honest single-pass block — see 14.3) and two
  `clippy::absurd_extreme_comparisons` (the same dead `> u32::MAX` check).
- `cargo clippy --fix` mechanical pass plus targeted manual fixes: doc-comment/
  blank-line issues, hex literal grouping, two genuinely-identical if/else
  arms merged, three deliberately-NaN-catching negated comparisons annotated
  with `#[allow(clippy::neg_cmp_op_on_partial_ord)]` and a comment (not
  "fixed" into a behavior change).
- **Remaining, not fixed**: ~50 `dead_code` warnings in `vg-layout` (14.3),
  and a handful of `too_many_arguments`/`type_complexity` warnings on
  internal geometry-heavy generator functions in `vg-layout`/`vg-ffi`
  (bundling their parameters into structs touches many call sites' call
  syntax; deferred rather than risking a "must stay identical" behavior
  change on a rushed refactor).
- **CI** (`run_linters.yml`) already runs `cargo fmt --check`, `cargo clippy
  --package verdigris --package vg-core --all-targets -- -D warnings` and
  `cargo test`, deliberately scoped to `verdigris`+`vg-core` only (the
  comment there: vendored `vg-gas` stays on upstream's own lint level, see
  `domains/gas/UPSTREAM.md`). `vg-layout`/`vg-heat`/`vg-power`/`vg-ffi` are
  original DQ code, not vendored, and arguably belong in that `-D warnings`
  gate too — but only once 14.3's dead-code cleanup lands, or the gate
  would immediately fail on the pre-existing warnings above. **Not changed
  this pass**; recommend widening the clippy package list in the same PR
  that removes the dead layout functions.
- **Also found, pre-existing, unrelated to this pass**: `cargo fmt --all
  --check` (the CI job right above the clippy one, unscoped) already fails
  on master — `ffi/callback` and `ffi/macros` are tab-indented with no
  local `rustfmt.toml` (unlike `domains/gas`, which has one matching
  vendored auxmos's own tab style), so default rustfmt's 4-space style
  disagrees with every line. Confirmed via `git show
  59ca56beef:verdigris/ffi/callback/src/lib.rs` — predates this audit
  entirely. New/edited code in those two crates on this branch matches
  their existing (tabs) style rather than default rustfmt, i.e. doesn't
  make the pre-existing gap any worse, but doesn't fix it either: that's
  either a repo-wide "add hard_tabs=true rustfmt.toml at the verdigris
  workspace root" decision or a reformat of those two crates, neither of
  which this audit's scope covers. Flagged, not touched.
- The `auxmacros` doctest failure noted in the worktree brief (missing
  `ByondValue`/`bind` context) was actually two doctests (the `bind` macro's
  own example was already `ignore`d): `auxcallback::callback_processing_hook`'s
  hook example and `auxmacros::generate_simd_functions`'s example, both
  illustrative snippets that need the FFI crate's macro/byondapi context.
  Both marked `ignore` with a one-line reason. `cargo test --workspace
  --doc` is green.

### 14.6 Verification

`cargo build`/`cargo test --workspace --target i686-pc-windows-msvc`
(including doctests) is green throughout; `cargo test -p vg-gas --features
turf_processing,heat` and `cargo test -p vg-layout` (host target) spot-
checked after each behavior-adjacent change. See the branch's commit
history for the per-concern breakdown.

## 15. Core consolidation: what domains may not build themselves

Every domain (gas, power, heat, radiation, and later ones) builds only its
physics, its component and grid declarations, and its topology rules (for
example pipe layers or cable directions). These mechanisms live once, in
`vg-core` (or the R10 binding layer), and a domain crate may not define its own:

| Mechanism | Core home | Replaces |
|---|---|---|
| Identity | R10 entities, components and generation-checked handles | gas device ids and SSair's string map; power's DM-allocated keys and side HashMaps; heat's hand-rolled body and watch handles |
| Activity and sleep | a core activity service: wake on input, setting or endpoint change, sleep when settled | gas's per-cell and per-device activity maps; power's missing one |
| Change tracking | `core::watch` (revisions, bands, thresholds) | gas's three `revision()` implementations and band tracking; power's "shown" diff copies |
| Rate models | a core rate-model library (flow toward a target with a rate limit and a stop condition; storage charge and discharge) | gas Flow internals, power APC/SMES constants and passes, the heat regulator |
| Thermo | a core thermo module (the pair-exchange law, constants, unit types) | heat's two exchange laws, gas's constant copies, per-domain unit conversions |
| FFI | the R10 generator (typed commands, reads, queries, outbox events) | positional `kind + p0..p3` formats, opcode lists, fixed-stride event records |
| Presentation | none: DM reads values when it displays them | display smoothing and "shown" copies inside simulation steps |

Enforcement is a CI check over `verdigris/domains/*` that fails on local
handle types, activity maps, revision counters, raw `#[bind]` FFI marshalling
or display smoothing in a domain crate. The domains migrate in this order:
gas devices (M2), power (a rewrite onto one generic producer, consumer and
storage rate model with R10 components; all DM mirrors and `power_sync()` are
deleted), heat (binds move out of vg-gas; heat bodies become components; the
regulator is wired to air conditioners, heaters and thermoregulators, or
deleted), then turf gas and heat as grid kinds.

## 16. §15 extensions landed by the rustaudit pass

Extending §15's table with three more entries, and reporting what
`rewrite/rustaudit` actually built against it (a CI-enforced architecture
check, plus the two entries it had the most direct evidence for already:
change tracking, since GasCell's `revision()` was mid-investigation when
this was scoped in, and thermo, since heat-r10 needed to know where to
build). Units-everywhere and the activity/sleep service are scoped and
documented here but **not implemented** by this pass -- see 16.4.

| Mechanism | Core home | Replaces |
|---|---|---|
| Units everywhere | `vg_core::units`, `f64`-backed, the *only* way a quantity crosses a module or FFI boundary | raw `f32` physical quantities in domain public APIs (flagged by the consolidation check once a domain migrates) |
| Conservation audit | `vg_core::conservation::Ledger` | ad hoc per-test `close()`-style diff helpers a domain writes for itself |
| (already in the original table, landed this pass) | `vg_core::thermo::pair_exchange`/`pair_exchange_at_rate`, `vg_core::revision::BandRevision` | vg-heat's two exchange laws; one of gas's three `revision()`s |

### 16.1 Change tracking: `core::revision::BandRevision`

`core::watch::Cond::Band` is the right tool for a *registered* condition
evaluated through the frame/channel/outbox pipeline (§6). `GasCell`'s
`revision()` is a cheaper, unregistered sibling: "bump a `u32` when
pressure/temperature/total moles moved past a band since the last bump",
read directly by an FFI bind, no registration or frame evaluation involved.
Generalized into `core::revision::BandRevision<const N: usize>`
(`core/src/revision.rs`): N independent scalar channels, each with its own
band; a `None` value that call never triggers or blocks the others; NaN
never triggers. `GasCell`'s `revision: u32` + `rev_at: [f32; 3]` fields
became one `bands: BandRevision<3>` field; `band_check` is a two-line call
into `bands.update(...)`.

Of gas's three `revision()`s, this is the only one that's actually
band-based. `world.rs`'s per-"Main"-slot revision and `pipes.rs`'s per-node
revision are both plain bump-on-every-write generation counters -- a
different, simpler shape `BandRevision` doesn't fit as-is. Left as-is and
allow-listed (16.3); `pipes.rs` is also one of M2's concurrently-edited
files regardless.

### 16.2 Thermo: `core::thermo::pair_exchange`

See the branch's commit `efe6e5b1ee`. `core::thermo` already had
`exchange(a, b, coefficient)` (instant relaxation by a precomputed
fraction) but not the conductance+`dt` form vg-heat's `couple.rs` actually
uses (`pair_exchange(ta, ca, tb, cb, g, dt)`, deriving the fraction itself
via `1 - e^(-g(1/Ca+1/Cb)dt)`, correct for a reservoir side). Added
`pair_exchange`/`pair_exchange_at_rate` to `core::thermo` on the module's
`ThermalBody`/`HeatCapacity`/`Kelvin` types, with the property tests ported
over; `vg_heat::couple::pair_exchange`/`pair_exchange_at_rate` are now thin
`f32`-signature wrappers over them. `rewrite/heat-r10` was pointed at this
location and API directly (message relayed by the coordinator).

Gas's own thermal constant copies (`domains/gas/src/gas/constants.rs`) are
not migrated onto `vg_core::units`/`thermo` by this pass.

### 16.3 The consolidation CI check

`tools/ci/check_rust_core_consolidation.py` + `tools/ci/rust_core_consolidation_allowlist.txt`
(wired into `run_linters.yml`, no Rust toolchain needed -- pure grep, runs
alongside the other Python lints). Five heuristic categories over
`verdigris/domains/*/src/**/*.rs`: `handle` (a domain-local generation-
checked handle/id type), `revision` (a domain-local bump counter),
`activity` (a domain-local per-entity awake/asleep map), `ffi_raw`
(positional `kind + p0..p3` FFI marshalling), `smoothing` (a domain's own
"shown" display-smoothed copy of a value). This is a grep, not a type
checker: a real hit that isn't actually a violation should narrow the
pattern, not get allow-listed.

Current allow-listed offenders (one per line in the allowlist, with the
branch/plan that removes it; a stale entry -- nothing matches it any more
-- fails the check too, so the list only shrinks):

- `domains/gas/src/pipes.rs` (`revision`): the pipe-node generation
  counter; M2's territory regardless.
- `domains/gas/src/world.rs` (`revision`): the "Main"-slot generation
  counter; needs its own core primitive (a plain version counter, not
  band-based), not built this pass.
- `domains/power/src/world.rs` (`smoothing`): `shown_brown`/`shown_apc`/
  `shown_smes` -- exactly "power's 'shown' diff copies" from §15's
  original table. Removed when power's rewrite lands.

No `handle`/`activity`/`ffi_raw` hits were found against the current
tree with these patterns; that's a heuristic gap (these patterns are
narrow, to avoid false positives on unrelated code -- e.g. `smooth_map` in
`vg-layout`'s cellular-automaton map generator, or `smooth_department_claims`
in the dead code removed by this same pass, are *not* the "display
smoothing" §15 means), not a claim that no such code exists. Tightening
these patterns (or adding new categories, e.g. for the R10 identity
system's arrival) is expected as domains migrate and more examples of each
violation become concrete.

### 16.4 Not implemented by this pass

- **Units everywhere (new §15 row).** Making `vg_core::units` the *only*
  way a physical quantity crosses a module or FFI boundary is a real
  `f32`-\>`f64` API change to every unit newtype (`Kelvin`, `Joules`,
  `HeatCapacity`, `Moles`, plus new `Watts`/`Kpa`/`Liters`/`Seconds`), and
  `core::thermo` (just landed, 16.2) and every consumer of it (`vg_heat`,
  soon `heat-r10`) would need updating in lockstep. Attempting this as a
  drive-by in an already-large pass risked a half-converted state across
  crate boundaries I don't own (bindings, heat-r10, power-r10) with no way
  to verify the other sides. Scoped and named here; not started.
- **Activity and sleep service.** Gas's own activity/wake tracking (the
  field's active-cell sets, `simulation.md` §1/§4's "urgent/fresh/frontier
  lanes", already partly on `core::field`'s active-set machinery per
  §13's table) and its per-device equivalent were not audited in enough
  depth this pass to design a correct generic replacement -- doing so
  without fully understanding the field framework's existing active-set
  invariants risks a live-simulation correctness bug (frozen or
  perpetually-active gas cells) that only a full DM atmos run would catch,
  and the test-budget rule for this pass is one DM run, at the very end,
  for everything above combined. Scoped in §15's table; not started.
- **Rate-model library** (for `rewrite/power-r10`): not built. The
  coordinator is relaying between agents; if `power-r10` hasn't produced
  one by the time this lands, that coordination should happen as its own
  piece of work, not a rushed addition here.

