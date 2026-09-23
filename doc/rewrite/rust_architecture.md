# Verdigris architecture: domains are declarations + laws

Status: **authoritative**. This document supersedes the overlapping parts of
`rust_core.md` §14–§16 and `rust_bindings.md` wherever they disagree. The
inventory that motivated it (every file, its size and its duplicates) is in
the lead's research notes. The findings are summarised in §1.

## 1. Why

Core already contains most of the machinery: incremental graphs
(`network/graph.rs`), grid fields with chunk sleep (`field/`), frames, watches,
outbox, rate models, thermo, units and conservation. The domains do not sit on
it. Each wraps core in its own host: its own key tables, handle schemes, `Sim`,
pacing, flat `Vec<f32>` event streams, dirty tracking and display state. That
private host code is about **60% of every domain's lines**. Every concept below
exists two to five times:

| Concept | Copies today |
|---|---|
| DM key → node tables | `network/host.rs` (unused), `gas/pipes.rs`, `power/world.rs` |
| Handles / slabs | `core/handle.rs` (20+4), heat `BodyHandle` (16+8), gas `Mains`, gas pipe slots, power DM keys, `entity.rs` `CellAllocator` |
| Region state through merge/split | `NetworkKind::merge/split` vs power's hand-remapped side `ledgers` map |
| Change tracking | `watch.rs`, `revision.rs`, gas `Signature`/`Dirty`, gas `Mains` revisions, pipe revisions, power `shown*` |
| Watch APIs | `watch::Cond`, heat `WatchCond`, gas `MixWatches` |
| Sims / pacing | gas `Sim`, heat `Sim`, one `Sim` per component kind, power has none |
| Events out | core `outbox` vs four different flat `Vec<f32>` encoders |
| Domain registries | ffi `ExternalDomain` vs ffi `EntityDomain` |
| Flux kernels | `field/kernel.rs` vs gas `cell.rs` `bulk`/`diffusion` |
| Thermal exchange | `core/thermo.rs` vs `heat/couple.rs` vs `Mixture::share_ratio` |
| Conservation | field reservoir ledger, heat `HeatLedger` + `Totals`, gas `Mains::totals` + `PipeNet::totals`, power `Books`, `conservation::Ledger` |
| Blocked masks | `grid::Grid` layers, each field's `Geom.blocked`, gas `masks` map, ffi radiation static |
| Constants | `TCMB`/`T0C`/`T20C` in gas and heat |

## 2. The rule

A **domain crate** contains exactly:

1. **Component declarations.** `#[vg::component]` structs with `config`, `input`
   and `state` fields, all with units.
2. **Kind declarations** for its networks and fields: `NetworkKind` (summary,
   payload, split/merge policy, connection rule) and `FieldKind` (cell state,
   flux law).
3. **Laws.** Pure functions `fn(&mut LawCtx<Reads, Writes>, dt)`.
4. **Event declarations.** A `#[vg::events]` enum.
5. **Rust tests** for the laws.

A domain crate **may not**:
- depend on `byondapi`, or contain `thread_local!`, `static mut`, or `#[bind]`;
- construct a `Sim`, pace itself, keep key/handle maps (`HashMap<u32, _>` of
  identities), keep revision counters or dirty sets, or diff display state;
- return `Vec<f32>` or hand-encode anything for DM;
- define a unit constant or re-implement a core kernel.

CI (`tools/ci/check_rust_core_consolidation.py`) enforces every item above. Its
allow-list may only shrink.

**Line budgets** (non-test code). Exceeding a budget means infrastructure has
leaked into the domain.

| Domain | Today | Budget |
|---|---|---|
| power | ~1,600 | **≤ 400** |
| heat | ~3,000 (plus 600 of binds in gas) | **≤ 600** |
| gas | ~8,700 | **≤ 1,600** (mixture maths, registry and reaction data dominate) |

## 3. Crate map

| Crate | Owns | Depends on |
|---|---|---|
| `vg-core` | everything generic (§4) | nothing BYOND |
| `vg-gas`, `vg-power`, `vg-heat` | declarations and laws only (§2) | `vg-core` |
| `vg-ffi` + `vg-macros` | the only BYOND boundary: the domain registry, generated binds, event codec, world lifecycle | `vg-core`, domains, `byondapi` |
| `material_power.rs` | out of scope (DQ Medical-owned voltage solver) | — |

Cross-domain coupling is **not** a crate dependency. Gas does not depend on
heat. A coupling law declares that it reads components or cells of both
domains, and the driver runs it (§4.3).

## 4. vg-core

Existing modules keep their jobs unless listed here. Changes are:
- **K** keep;
- **M** merge into another module;
- **B** build;
- **D** delete.

### 4.1 Identity: one entity table (B: unify)

- `EntityTable` (from `rewrite/bindings`) is the **only** identity. An entity
  is anything DM binds: a machine, pipe, cable, item heat body or mob body.
- An entity owns a set of `ComponentRef{kind, row}`, at most one per component
  kind.
- **Handle encoding.** Handles cross to DM as a float, so they must be exact
  integers below 2^24.
  - The layout is 19 bits of slot (524k live entities) plus 5 bits of
    generation.
  - Freed slots go to a **quarantined FIFO**: a slot is reused only after 4,096
    other frees. Stale-handle aliasing would need 32 reuses of one slot, each
    behind a 4,096-free quarantine.
  - The lifecycle framework guarantees unbind before an atom dies
    (`lifecycle.md` phase 1).
  - The generation check therefore stays a debug assertion backed by a real
    check. It is not the only defence.
- Grid cells are **not** entities. They are addressed by `CellId` (coordinate
  index).
- **Delete:**
  - `core/handle.rs` (20+4) in favour of the entity handle, with a thin
    internal `Slot` type for arenas;
  - heat `BodyHandle`;
  - gas `Mains` slots;
  - gas pipe slot tables;
  - power DM keys;
  - `CellAllocator` as a separate concept: component rows live in each kind's
    store.

### 4.2 Component storage (B)

- There is one store per component kind: dense columns in a `cow::ChunkedStore`,
  indexed by row, with a row → entity back-map.
- **Owner per kind**, declared on the component:
  - `owner = worker`: stepped in frames. DM writes become commands, and DM reads
    see its own writes immediately through the overlay (the existing
    `owner.rs`/`overlay.rs`/`command.rs`, generalised off gas).
  - `owner = main`: main-thread synchronous. This is for things DM reads and
    writes immediately, such as tank and lung mixtures (today's gas `Mains`).
    The same component API applies, with no frame.
- **Take reconciliation**: when DM removes gas or charge between frames, the
  worker's view is corrected. This moves from `gas/world.rs:1717-1800` into core
  overlay behaviour and is generic for every conserved worker-owned column.

### 4.3 Laws and the driver (B)

```rust
pub trait Law: 'static {
    type Reads: Query;            // component columns, network payloads, field cells
    type Writes: Query;
    const NAME: &'static str;
    const PERIOD: Period = Period::Frame;   // or Period::Ticks(n), for APC/SMES cadence
    fn step(ctx: &mut LawCtx<Self::Reads, Self::Writes>, dt: Seconds) -> Settle;
}

world.add_law::<ApcTick>()
     .add_law::<PowerBalance>().after::<ApcTick>();
```

- **One `Sim` per DLL.** The driver owns pacing:
  - a fixed-dt accumulator;
  - idle skip;
  - a backlog cap;
  - per-law periods and declared ordering (`after`/`before`).

  Laws compile into `frame::Task`s, and their read and write sets come from
  their declared queries, which gives parallelism for free.
- A `LawCtx` iterates only **active** rows, regions or cells, and exposes:
  - `emit(event)`;
  - `wake(entity | region | cell)`;
  - `schedule(at, entity)`, the reactor timer path for `RateModel` crossings;
  - `ledger(quantity)` for explicit sources and sinks.
- **Specialised laws.**
  - `FieldKind` stays the monomorphised fast path for grid diffusion and is
    registered as a law over cells. There is no dynamic dispatch inside the flux
    loop.
  - `NetworkKind` region steps are laws over regions.
  - Device laws read `(Device, side A, side B)` through `Network::resolve`.
- **Coupling laws** (solid↔gas, body↔gas, pump power draw): they declare reads
  and writes across two domains' components or cells and are ordinary laws. This
  replaces gas `Exchange` (Mutex buffers), `heat::GasExchange`/`GasRef`/`GasProbe`,
  and the two different types both named `GasRef`.
- **Delete:**
  - the gas, heat and per-component-kind `Sim`s;
  - heat's tick accumulator;
  - gas's idle skip;
  - power's per-machinery-tick stepping.

### 4.4 Activity and sleep (B for entities and regions; K for fields)

- Fields already sleep per chunk (§16.5 of `rust_core.md`). Keep that.
- Each law has an `Activity` bitset over its domain (rows, regions or cells).
  Rows are woken by:
  - a command write to that row (automatic, since the command path knows it);
  - a region payload change (`drain_touched`, `graph.rs:774`, already tracks
    this);
  - a watch or reactor timer firing;
  - an explicit `ctx.wake`.
- A law returns `Settle::Sleep` to put a row to sleep. APC and SMES sleep
  between `RateModel` crossings, which the reactor schedules.
- **Delete:** gas's per-cell and per-device activity maps and power's
  step-everything loop.

### 4.5 Networks (A: graph; B: host keyed by entity)

```rust
pub trait NetworkKind {
    type Node: Component;             // Cable{d1,d2}, PipeSeg{volume,layer}
    type Summary: Additive;           // supply/demand/capacity; volume
    type Payload: Conserved;          // PowerLedger, PipeGas: ALL region state
    fn summarize(n: &Self::Node) -> Self::Summary;
    fn connects(a: (&Self::Node, CellId), b: (&Self::Node, CellId)) -> bool; // topology law
    fn split(p: &Self::Payload, parts: &[Self::Summary]) -> Vec<Self::Payload>;
    fn merge(into: &mut Self::Payload, other: Self::Payload);
}
```

- `NetworkHost<K>` replaces `network/host.rs`, gas `PipeNet` and power's
  `at`/`links` maps:
  - Nodes and devices are keyed by entity handle.
  - Edges are derived from `connects` over the grid-cell occupancy index. DM
    never sends topology: binding a component at a cell is enough.
  - It keeps `commit`'s split-then-merge batching, so explosions stay one batch.
  - Device iteration is dense over the device arena, not a hash lookup.
- **Rule:** no region state outside `Payload`. Power's brownout flag, ledger and
  view all live in the payload; `split` and `merge` are domain law.
- Pipenets and cables use the same host. Only the kinds differ.

### 4.6 Grids and fields (K; B: one grid owns masks)

- `FieldKind`/`add_field` are unchanged. Gas adopts `kernel::pressure_flow` and
  `kernel::diffusion`, and deletes `cell.rs` `bulk`/`diffusion`.
- There is one `grid::Grid` per z-level, and it owns every block layer.
  `Geometry<K>` reads `blocked` from `Grid::layer(K::BLOCK)`. **Delete** gas
  `masks`, per-field `Geom.blocked` copies and the ffi radiation `static`.
- Sleeping chunks must remain pointer-identical CoW shares. That pinned test
  stays.

### 4.7 Change tracking and presentation (M)

- There is one module, `watch`, and `revision.rs` merges into it as the
  "read-directly" variant. DM gets values through generated reads, and watches
  cover every "tell me when" case.
- **No presentation state in Rust.** Delete:
  - power `shown*` and 0.8/0.2 smoothing (these become a DM read-time concern);
  - gas `Signature`/`Dirty`;
  - heat's `WatchCond` wrapper;
  - gas `MixWatches`.

### 4.8 Events (A: outbox; B: typed codec)

- Domains declare `#[vg::events] enum PowerEvent { Brownout{region}, … }` and
  call `ctx.emit`.
- The generator produces the DM decoder and handler dispatch. This is on the
  `rewrite/bindings` WIP commit `6642304484` and becomes the only path.
- **Delete** power `ev::*`/`push`, gas's flat tick encoding, heat
  `take_wakes(&mut Vec<f32>)` and every `-> Vec<f32>` return.

### 4.9 Conservation (A: `Ledger`; B: auto-wire)

- `trait Conserved { fn totals(&self, out: &mut [f64]); }` is implemented by
  field kinds, network payloads and conserved component columns.
- The driver sums each declared quantity after every frame and calls
  `Ledger::check` in debug and test builds.
- Cross-domain transfers are a sink in one domain and a source in the other,
  both recorded by the coupling law.
- **Delete** `HeatLedger`, `Totals`, `Books`, and the `Mains`/`PipeNet` totals.
- Known bug to fix under this: power `tests::the_ledger_conserves` has a
  confirmed conservation failure (proptest regression on file).

### 4.10 Rate models (M)

- `reactor::RateModel` (Linear, Relax, Sum, with exact crossings) and power's
  new `rate::RateStore` merge into one `core::rate` module. Storage (cells, SMES)
  is `RateModel::Linear` between events, and relaxing bodies are `Relax`.
- **Delete** heat `regulator.rs`'s private rate logic (the Regulator becomes a
  law) and the SMES/APC hand integration.

### 4.11 Units, constants, thermo (K; M constants)

- `units` (f64 newtypes) and `thermo` stay. `units::consts` holds `T0C`,
  `T20C`, `TCMB`, `R` and Stefan–Boltzmann. Delete the gas and heat copies.
- Hot columns may store `f32`. Laws widen to f64 and component fields declare
  `unit =`, which the macro enforces at the boundary.

### 4.12 Unchanged

`arena`, `bitset`, `channel`, `cow`, `frame`, `intern`, `jobs`, `mailbox`,
`metrics`, `recorder`, `replay`, `rng`, `timer`, `propagate`, `alloc`.

## 5. vg-ffi and macros

- **One `DomainRegistry`**, merging `ExternalDomain` and `EntityDomain`. Each
  domain registers its kinds, laws and events.
- `#[vg::component]` generates everything `kind/pump.rs` writes by hand today:
  - the store;
  - get/set/describe;
  - the query groups;
  - validators;
  - the bind and unbind glue.
  A component crate writes the struct and nothing else. The target is that
  `pump.rs` goes from 393 lines to ~25.
- The generator (`tools/build/lib/verdigris_bindings.ts`) emits the whole DM
  surface: typed accessors, `init_*`, reconcilers, event dispatch and the ABI
  hash. There are no hand-written `#[bind]` procs for domain data.
- The legacy gas mixture API (~60 binds that DM calls directly) is expressed as
  a `GasMix` component (`owner = main` for tanks and lungs) plus queries, and
  `lib.rs` shrinks to the generated surface.

## 6. What each domain becomes

### Power (≤ 400 lines)

- **Components:** `Cable{d1,d2}`, `Apc{channels: [ChannelCfg; 3], cell: RateModel, …}`,
  `Smes{input, output, charge}`, `Consumer{demand, priority}`, `Producer{supply}`.
- **`NetworkKind`:** `Cables`, whose payload is `PowerLedger`.
- **Laws:**
  - `PowerBalance`, per region: generators plus storage offers, then consumers
    in priority order, then storage input pro rata, then storage output last,
    then brownout. About 80 lines.
  - `ApcTick`: the channel autoset ladder and charge mode. About 120 lines.
  - SMES input/output planning. About 40 lines.
  - The cable connection rule (from `geom.rs`). About 60 lines.
- **Events:** `Brownout`, `Restored`, `ApcChannelChanged`.

### Heat (≤ 600 lines)

- **Components:**
  - `HeatBody{capacity, temperature, …}` for items, turfs' contents and
    machines;
  - `MobHeat` (DQ Medical's H2 requirements: fluxes in W, setpoint, sweat and
    shiver capacity, comfort bands as watch thresholds, time scale);
  - `Regulator{max_power, cop, target}`.
- **`FieldKind`:** `Solid`, covering conduction plus radiation to space.
- **Laws:**
  - body↔environment exchange (`pair_exchange`, and `Relax` against a
    reservoir);
  - the phase buffer;
  - `Regulator` as a heat pump (`W·COP` moved, `W·(1+COP)` dumped);
  - coupling laws solid↔gas and body↔gas.

### Gas (≤ 1,600 lines)

- **Mixture maths:** ~250 lines.
- **Registry and types:** ~300 lines.
- **`FieldKind`:** `TurfGas`, using core kernels. About 80 lines.
- **`NetworkKind`:** `Pipes`, whose payload is `PipeGas`.
- **One device flow law:** move gas from side A to side B, rate-limited by
  power or conductance, until a pressure condition holds. Pump, valve, filter,
  mixer, vent, scrubber and regulator are configurations of it, about 20 lines
  each.
- **Reactions:** gating, fire and fusion. About 300 lines, mostly data.

## 7. Migration plan and ownership

Ordering: core pieces land behind stable APIs first, and domains write their
laws as **pure functions with Rust tests immediately**, since laws don't need
the infrastructure. Once core lands, domains delete their private host code
and plug the laws in.

| Track | Owner (agent) | Scope |
|---|---|---|
| **Core A**: driver | rustaudit | `Law`/`LawCtx`/`Settle`/periods and ordering; one `Sim`; activity bitsets and wakes; conservation auto-wiring; `rate` merge; `watch`+`revision` merge; `units::consts`; extend the CI check (§2) |
| **Core B**: identity and boundary | bindings | unified `EntityTable` (19+5 bits, quarantined FIFO); component stores with owner main/worker; overlay, commands and take reconciliation generalised; `DomainRegistry` merge; macro-generated stores and glue; typed events; generator |
| **Core C**: topology | power | `NetworkHost<K>` keyed by entity with connection-rule edges; one `Grid` owns block layers; then the power domain |
| **Heat domain** | heat | laws now (pure plus tests); then `Solid` on the unified grid, `HeatBody`/`MobHeat`/`Regulator` components, coupling laws; delete `world.rs` host, `BodyHandle` and gas's `heat.rs` |
| **Gas domain** | M2 | laws now (device flow law, mixture, reactions, `TurfGas` on core kernels); then `PipeGas` on `NetworkHost`, `GasMix` main-owned component; delete `world.rs` host, `pipes.rs`, `Mains`, `Signature`/`Dirty` and `lib.rs` binds |

**Testing during the Rust phase:** only `cargo test` and `cargo clippy -D warnings`.
Every law gets property tests (conservation, monotonicity, no overshoot) and
scenario tests on a host-only world. No DreamDaemon runs until the whole Rust
side is done. After that the DM side is migrated and everything is tested
together once test isolation and speed have landed and master is green.

**Definition of done** for the Rust phase:
- the CI consolidation check passes with an **empty** allow-list;
- the line budgets are met;
- all law, property and scenario tests pass;
- no domain depends on `byondapi`;
- `pump.rs` is under 30 lines.
