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
