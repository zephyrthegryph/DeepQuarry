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

## 8. Consolidation plan (2026-09)

This section records the September 2026 audit of the branch after the first
round of core work, and the ordered plan that finishes the consolidation. It
refines §7: §7 says *who*, this says *what is left and in which order*.

### 8.1 Audit: where the lines are

Every domain is still **60–75% generic machinery**. Budgets are §2's; the
"realistic" column is what the declarations and laws alone come to once the
machinery below is gone.

| Domain | Non-test lines today | Budget | Realistic after the plan |
|---|---|---|---|
| gas | ~7,850 | 1,600 | ~1,600–1,900 |
| heat | ~3,900 | 600 | ~600–700 |
| power | ~970 in `domains/power` + ~1,100 in `ffi/src/power.rs` | 400 | ~400–450 |

Power's host did not disappear, it **moved** to `ffi/src/power.rs`:
`PowerHost`, the `storage_offer`/`asks` maps, its own `step`, the
`push_changed`/`reported` presentation diffing, a `Vec<f32>` encoding, a
`thread_local!` and positional `apply`. The CI check
(`tools/ci/check_rust_core_consolidation.py`) only scans `domains/*/src`, so
none of that is caught.

**Duplicated machinery** (each row is one generic facility implemented
several times):

| Concept | Copies |
|---|---|
| Handles | heat `BodyHandle`, `mob::pack`, heat watch slots, gas `Mains`, pipe `slot_of`, reactor `Tokens`, `EntityTable` (7) |
| Sim / pacing | gas world, heat world, heat mob, `body::add_bodies`, `PowerHost::step`, reactor `Host::step`; `law::Pacer` exists and is unused (6) |
| Networks | gas `PipeNet` vs `NetworkHost` |
| Watches | gas `MixWatches`, heat `WatchCond`, reactor `ProbeDomain`, `core::watch` (4) |
| Dirty / presentation | gas `Signature`/`Dirty`, power `reported` |
| Events out | gas `Post`/tick encoding, heat `take_wakes` ×2, power `push`, reactor list vs outbox (5) |
| Conservation | `HeatLedger`, `Totals`, `PipeNet` totals, `Mains` totals vs `conservation::Ledger` (5) |
| Thermal exchange | `heat/couple.rs` `pair_exchange` vs `core/thermo.rs`; regulator stepping vs `laws::regulator_step`; `temperature_of`/`energy_at` vs `laws::phase_*` |
| Probes | 3 |
| Constants | `units.rs` defines `TCMB` twice |

**Crate-map violations.** `vg-gas` depends on `vg-heat` and `vg-ffi`
(forbidden by §3). The allow-list holds **21 entries**: 16 gas (the
`byondapi` dependency, 5 `bind_attr`, 4 `thread_local`, 2 `key_map`, the pipes
revision counter, `dirty_set`, `sim_construct`, `vec_f32_return`) and 5 heat
(`key_map`, 2 `sim_construct`, 2 `vec_f32_return`), plus heat's handle
constants and packing, which the check does not catch.

**Core gaps** (why the domains could not port yet):
- laws were not executed as `frame::Task`s over component-store columns: the
  `Query` trait was an open marker;
- no single driver owned the `Pacer`, activity, `Settle::Sleep`, periods and
  ordering;
- component stores had no declared owner (`main`/`worker`) and no take
  reconciliation;
- the typed event codec and DM generator were not the only event path;
- conservation was not auto-wired;
- `grid` had no block layers addressed by `CellId`/`Dir`;
- `RateModel` and `RateStore` were not merged.

**`layout` is not a sim domain.** It is the procedural station/cave generator
(~11,500 lines). It moves to `verdigris/gen/layout`, is exempt from the domain
rules and budgets, and its largest files are split.

### 8.2 Steps

| Step | Scope | Depends on |
|---|---|---|
| 0 | Differential harnesses per domain (old host vs new driver on recorded scenarios). **Deferred**: testing comes after the Rust implementation. | — |
| 1a | Core driver: `Law`s run as `frame::Task`s over component columns through a finished `Query`; one `World` owning `Pacer`, activity bitsets, `Settle::Sleep`, periods and ordering; conservation auto-wired (ledgers checked after each frame); one `units::consts`; one rate module; `thermo` as the only exchange math (`phase_*`, `pair_exchange`, regulator stepping). | — |
| 1b | Core bindings: component stores with a declared owner and take reconciliation; one `DomainRegistry`; `#[vg::component]` generating the whole binding with no `byondapi` in the domain crate (`pump.rs` < 30 lines); typed event codec + DM generator as the only event path; generic entity handles (reactor tokens, heat bodies and watches); one watch facility covering the `MixWatches`/`WatchCond`/`ProbeDomain` cases; a probe (field-read) facility; publishing without display-diff caches. | 1a |
| 1c | `grid::Grid` block layers (masks) with `CellId`/`Dir` addressing; absorbs power `geom.rs`'s generic parts. | — |
| 2 | Heat dedup onto core `thermo`. | 1a |
| 3 | Power onto the driver: delete `PowerHost`, `reported`, the hand binds. | 1a, 1b, 1c |
| 4 | Heat onto the driver; move heat's binds out of gas. | 1a, 1b, 2 |
| 5 | Gas pipes onto `NetworkHost`. | 1a, 1b |
| 6 | Gas: `GasMix` main-owned component + generated API; delete `lib.rs` binds, `turf.rs`, `Mains`, `Dirty`, `MixWatches`, `Post`; drop `byondapi`. | 4, 5 |
| 7 | Reactor FFI: `Tokens` → entity handles, `Probe` → watches. | 1b |
| 8 | Move `layout` to `gen/`, split its largest files. | — |
| 9 | CI: line budgets, crate-dependency checks, `ffi/` scanning; the allow-list is empty. | 3–7 |

About **120 agent-hours** in total. The critical path is **1b → 4 → 6 → 9**.

### 8.3 Status

- **Done on `rewrite/rust-core2`:** 1a, 1b, 1c (every core facility, §8.4),
  2 (heat's exchange math is core `thermo`'s) and 8 (`gen/layout`, with
  `structural.rs` and `content.rs` split by pipeline stage). The workspace
  builds on the host and on i686 (`cargo check --workspace --all-targets`).
- **Open:** 0, 3, 4, 5, 6, 7, 9. These are domain ports onto the facilities
  below; §8.5 lists what each port does. No further core work is expected.
- **Not yet exercised:** nothing here has been run. Per the plan, tests
  and differential harnesses (step 0) come after the implementation; the
  crates only compile, with their existing and new unit tests building.

### 8.4 Facilities

Each entry names the module, its API and what a domain does with it.

#### The driver: `vg_core::world`

One `World` per DLL (`vg-ffi` keeps it; `world::with_world`). It owns the
entity table, every component store, networks, globals, the grid, fields,
the only `Pacer`, and every law.

```rust
let mut b = WorldBuilder::new(WorldConfig { dt: Seconds(1.0), backlog_cap: 2, .. });
let apc = b.add_component::<Apc>();                  // KindId; owner from the declaration
b.add_network::<Cables>(Ownership::Main);           // NetworkHost<Cables> in the main phase
b.add_grid(dims);                                   // the one Grid (block layers, z links)
let solid = b.add_field::<SolidHeat>(config);       // blocked faces from grid layer K::BLOCK
b.watch_field(solid);                               // turf temperature watches
b.add_global(Ownership::Main, RadiationLayer::default());
b.add_law::<ApcTick>();
b.add_law::<PowerBalance>().after::<ApcTick>();
b.conserve("energy", Tolerance::default());
b.conserve_network::<Cables>();
let mut world = b.build()?;                         // laws that name unregistered or other-phase data fail here

world.tick(elapsed);                                // once per DM tick: pace, main phase, dispatch worker frame
let e = world.bind(None, apc, &[(field, None, value)])?;
world.get(e, apc, field, 0)?; world.set(e, apc, field, None, v)?; world.adjust(e, kind, field, 0, -3.0)?;
world.read::<Apc>(e); world.put(e, value)?; world.submit::<Apc>(e, &cmd)?;
world.watch(kind, subscriber, lane, &cond)?;  world.drain_wakes(&mut wakes);
world.drain_events();                               // EventSink: the one wire list for DM
world.violations();                                 // conservation, per phase
world.edit_network::<Pipes>(|host| ...)?; world.drain_transitions::<Pipes>();
world.edit_grid(|g| g.set_blocked(BlockKind::Air, cell, Dir::ALL))?;
world.read_cell(solid, cell); world.submit_cell(solid, cell, cmd)?;
world.spawn()? / world.despawn(e)?                  // generic handles (reactor tokens, probes)
world.law_stats();                                  // stepped/awake per law
```

- **Two phases.** Data owned by the main thread (main-owned components,
  main networks such as pipes and cables, main globals) is stepped by
  main-phase laws, run synchronously inside `tick`; worker-owned data is
  stepped in the frame on the pool. A law's phase is its anchor's owner. The
  phases run in lockstep, one step per tick at most; DM never waits.
- **Pacing.** `WorldConfig::dt` and `backlog_cap` feed the only `Pacer`;
  `Period::Ticks(n)` laws become `Task::every(n)` with `dt * n`.
- **Ordering.** Registration order, constrained by `after`/`before`
  (`order_laws`); within a phase the frame schedule runs laws with disjoint
  access in parallel and orders the rest.
- **Conservation.** `conserve(name, tolerance)` declares a quantity.
  Sources are summed automatically: every component field declared
  `conserve = "name"` (both owners), `conserve_network::<K>()` payloads,
  fields registered with `FieldKind::QUANTITY_NAMES` (cells plus reservoir
  inflow), and `conserve_resource`. Sinks and sources are what laws record
  through `ctx.ledger()` plus every DM command's effect on conserved fields,
  measured when the command is applied (`Domain::conserved`,
  `DomainState::crossings`), so DM taking gas is a crossing, not a leak.
  Checked after every step when `check_conservation` is on (debug and test
  builds by default).
- **Known gap.** The flight recorder records domain command batches only;
  the world's own per-dispatch inputs (row presence, DM wakes, network
  edits, the grid snapshot) are not recorded, so `Sim::replay` cannot yet
  replay a world session.

#### Laws and queries: `vg_core::law`, `vg_core::query`

```rust
pub trait Law: 'static {
    type Reads; type Writes;                       // plain types in tests; Query/WriteQuery to register
    const NAME: &'static str;
    const PERIOD: Period = Period::Frame;
    fn step(ctx: &mut LawCtx<'_, Self::Reads, Self::Writes>, dt: Seconds) -> Settle;
}
ctx.reads / ctx.writes
ctx.emit(event) / ctx.emit_for(entity, event)      // typed events
ctx.wake(index) / ctx.wake_entity(entity)          // this law's item / every row law's entity
ctx.schedule(at) / ctx.schedule_crossing(&model, level) / ctx.schedule_store(&store, rate)
ctx.ledger()                                       // sources and sinks
LawCtx::new(&reads, &mut writes, &mut Effects::default())   // a law's own tests
```

| Query | Anchor | Fetch / write |
|---|---|---|
| component `C` | rows of `C` | the item entity's row; written back only if changed |
| `Option<C>` | — | a join that may be absent |
| `Global<T>` | once per step | a whole global (`Clone + PartialEq`) |
| `Payload<K>`, `Summary<K>` | regions of `K` | a region's pooled state / aggregate |
| `Members<K, C>` | regions of `K` | every member entity's `C` row (read-only) |
| `InRegion<K>` | — | the region the item entity's node is in |
| `Sides<K>`, `DeviceData<K>` | devices of `K` | both regions a device joins; its parameters |
| `RegionCell<K, F>` | devices of `K` | a region ↔ field-cell device (vents) |
| `Cell<F>` | active cells of field `F` | one field cell; a second `Cell<G>` joins field `G` at the same cell |
| tuples of the above | first anchor | all of them |

The first query in `Writes` (else `Reads`) with an anchor decides what the
law iterates:
- **rows** iterate the law's activity bitset: an item is woken by a bind, a
  DM write to it, a timer, `wake`, or any law's `wake_entity`, and sleeps
  when the step returns `Settle::Sleep` (or its data is gone);
- **regions and devices** iterate densely and skip items whose revision
  (payload, summary, membership, parameters, either side for a device) has
  not moved since they last ran, unless awake;
- **cells** iterate the field's active chunks.

A worker law may read main-owned data (a snapshot taken at dispatch) and a
main law may read worker-owned data (the view pinned this tick); neither may
write the other phase's data (`LawError::WrongOwner` at build).

#### Components and stores: `vg_core::component`, `vg_core::store`, `#[vg::component]`

```rust
#[vg::component(domain = gas, kind = 1, dm = "/obj/machinery/atmospherics/binary/pump",
                owner = worker, computed = [pressure])]
pub struct Pump {
    #[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp, hysteresis = 1.0)]
    target_pressure: f32,
    #[vg(state, unit = "mol", conserve = "gas_moles")]
    held: [f32; N],
}
```

generates, with no `byondapi` in the domain crate: `Default`, `PumpKind`
(the `Domain` marker, with `conserved`), `PumpCommand` (per-field variants,
`FieldAt` for arrays, `Adjust(field, index, delta)`), validators,
`impl Component` (`FIELDS`, `get_field`, `set_command`, `adjust_command`,
`conserved`) and `impl Channels for PumpKind` (one watch channel per numeric
field and computed readout). `kind/pump.rs` is 26 lines.

- **Rows are indexed by entity slot** (`store::kind_layout`), in
  copy-on-write chunks of 256, so joins across kinds need no map. §4.2's
  row → entity back-map is `store::Rows` (presence plus the full id).
- **Owners.** `owner = worker`: a domain of the one `Sim`; DM writes are
  commands through the overlay (read-your-writes). `owner = main`:
  `store::MainKind` on the main thread, written synchronously; worker laws
  read its dispatch snapshot (`store::WorkerKind`).
- **Take reconciliation** is `Adjust`: DM's removal is a delta applied to
  the owner's current value, clamped at zero with the shortfall reported,
  and recorded as a conservation crossing.
- Numeric domain ids are one table, `component::domains`; `domain_id` is a
  const fn, so an unknown domain is a compile error.

#### Events: `vg_core::event`, `#[vg::events]`

`#[vg::events(Pump)]` (component events) or `#[vg::events(domain = power)]`
(region/domain events); variants are unit or carry named numeric fields
(`#[vg(unit = "K")]` documents one). The macro implements `Event` (`id`,
`encode`, `decode`, `VARIANTS` schema). `EventSink` is the one wire format:
`header, entity, len, payload...` per record, `header = domain << 16 | kind
<< 8 | variant`. `World::drain_events` returns every law's events of the
step; `vg_world_events()` hands them to DM; the generator writes
`vg_drain_events()`, which dispatches component events to the bound atom
(`on_pump_starved()`) and domain events to `SSvg.on_power_brownout()`.

#### Watches and probes

- Every component kind is watchable (`World::watch`, cells = entity slots;
  from DM, the reactor's watch binds with `REACT_DOMAIN_<NAME>` and entity
  handles as cells). Worker kinds evaluate in the frame, main kinds after
  the main phase. This covers gas `MixWatches` (a `Changed`/`Threshold` on a
  `GasMix` row), heat `WatchCond` (a threshold on a body or a turf cell) and
  the reactor's `ProbeDomain` (a main-owned component DM writes).
- Fields are watchable with `WorldBuilder::watch_field` /
  `World::watch_cells`.
- The **probe** (field-read) facility: `World::get`/`vg_component_get_many`
  for component fields, `World::read_cell`/`submit_cell` for field cells,
  `Cell<F>` for laws. No domain keeps a `GasProbe`/`GasExchange` adapter.
- Nothing publishes presentation: DM reads current values through the
  generic reads; there are no display-diff caches.

#### Networks: `vg_core::network::{host, law}`

`NetworkHost<K>` gains region and device **revisions** (sleep until a side
changes), dense `devices()`/`regions()`, `set_payload` (moves the revision
only on a change), `device_pair`, cell devices (`bind_cell_device`),
`set_device_data`, `transitions(&events)` (DM-facing: members, prior
regions, retired, keyed by region handle), `take_released` (a removed
node's share, by entity and cell) and `impl Conserved` (payloads plus
unclaimed releases). This is everything gas `PipeNet` does by hand: device
steps are a device law over `Sides<Pipes>` (+ `DeviceData`, + the device's
own component such as `Pump`), vents are `RegionCell<Pipes, TurfGas>`,
totals come from `conserve_network`, and DM's rebuilds come from
`drain_transitions`.

#### Grid: `vg_core::grid`

`CellId` (the turf index), `Dir` (a BYOND direction: `reverse`,
`is_diagonal`, `planar`, `faces`; also a face set, replacing `DirMask`),
`Grid::step(cell, dir)` (diagonals and z links), and block layers that share
chunks copy-on-write and carry per-chunk revisions. Fields read their faces
from the world's grid (`FieldKind::BLOCK`) and wake exactly the chunks whose
revision moved. `Geom::blocked` remains only for hosts that predate the
grid and is deleted when gas and heat port.

#### Registry, rates, thermo, units

- `vg_core::registry`: `DomainRegistry` and `Registry` live in core (a
  domain crate can implement it without depending on `vg-ffi`); `vg-ffi`
  keeps the one instance. The world is registered under
  `entity::WORLD_DOMAIN` (lifecycle) and `registry::world_kind_domain(code)`
  per kind (watch ports).
- `vg_core::rate`: `RateStore::flow`/`next_bound` with
  `LawCtx::schedule_store`; `RateModel` for the reactor and relaxing bodies.
- `vg_core::thermo`: the only exchange math (pair exchange, `Phase` plateau,
  `relax_toward`, `thermo::regulator`).
- `vg_core::units::consts` is the only home of `TCMB`/`T0C`/`T20C`.

#### FFI: `vg-ffi`

- `world.rs`: the World, the **registration list** (`register`: the one
  place every domain's declarations are added), and the generic binds:
  `vg_component_bind/detach/has/get/get_many/set/adjust`,
  `vg_world_tick/events/violations/laws`. There are no per-component binds.
- `entity.rs` works on the world's entity table.
- `vg-gas` no longer depends on `vg-ffi`; `vg-ffi` depends on the domains
  and registers gas's turf watch port.
- The DM generator emits `VG_KIND_<NAME>` codes, field ids and typed
  wrappers over the generic binds, plus the event dispatcher.

### 8.5 What each domain does to port

- **Power (step 3).** Declare `Cable`, `Apc`, `Smes`, `Consumer`,
  `Producer` as `#[vg::component(domain = power, owner = main)]`; register
  `add_network::<Cables>(Ownership::Main)`. Move the ledger, brownout flag
  and storage offers into `PowerLedger` (the payload). `PowerBalance`
  becomes a region law: `Reads = (Members<Cables, Consumer>, Members<Cables,
  Producer>, Members<Cables, Smes>)`, `Writes = Payload<Cables>`. `ApcTick`
  is a row law over `Apc` with `InRegion<Cables>`, sleeping on
  `ctx.schedule_store(&apc.cell, net)`. Events are `PowerEvent`
  (already typed). Replace `geom::pos` with `CellId` and `Grid::step`.
  Delete `ffi/src/power.rs`'s `PowerHost`, `storage_offer`/`asks`,
  `push_changed`/`reported`, the `Vec<f32>` encoding and the thread-local;
  DM uses the generated accessors.
- **Heat (step 4).** `SolidHeat` registers with `WorldBuilder::add_field`
  (`BLOCK = BlockKind::Heat`, `QUANTITY_NAMES = ["heat_energy"]`) and
  `watch_field`; bodies become a `HeatBody` component (worker), mob bodies
  `MobHeat`, the regulator a `Regulator` component whose law calls
  `thermo::Regulator::step`. Couplings are laws: solid↔gas over
  `(Cell<SolidHeat>, Cell<TurfGas>)`, body↔environment over `HeatBody` rows,
  analytic bodies sleep with `ctx.schedule_crossing(&relax_model, level)`.
  Delete `world.rs`'s host, `BodyHandle`, `HeatLedger`/`Totals`,
  `take_wakes`, the handle constants, `couple.rs`'s `GasExchange` and gas's
  `heat.rs` binds.
- **Gas pipes (step 5).** `Pipes` on `add_network::<Pipes>(Ownership::Main)`,
  `PipeGas: Conserved`, `conserve_network::<Pipes>()`; the flow law as a
  device law over `(Sides<Pipes>, DeviceData<Pipes>)` or the device entity's
  component, vents as `RegionCell<Pipes, TurfGas>`. Delete `PipeNet`'s
  maps, `seen`/`revisions`, slots and `commit`'s transitions (use
  `drain_transitions`).
- **Gas (step 6).** Tanks and lungs bind `GasMix` (main-owned, done);
  `TurfGas` registers with `add_field` over the grid; `MixWatches` become
  world watches; `Post`/tick encoding become `GasEvent`s; `lib.rs`'s legacy
  binds become `GasMix` accessors and queries. Then drop `byondapi` and the
  `vg-heat` dependency.
- **Reactor (step 7).** `Tokens` → `World::spawn`/`despawn`; `ProbeDomain` →
  a main-owned `Probe` component with world watches.
- **CI (step 9).** Budgets, crate-dependency checks (no domain depends on
  `vg-ffi`, `byondapi` or another domain) and scanning `ffi/src`; the
  allow-list reaches empty as 3–7 land.
