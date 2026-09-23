# Simulation domains (track M)

Every simulation sits on two shared frameworks from `vg-core`: **fields**, which live on the grid, and **networks**, which are made of ports and edges. A domain supplies its data and its physics; the frameworks handle activity, conservation, scheduling, publication and watches. This document covers the frameworks and each domain built on them.

## 1. Field framework

```rust
pub trait Field {
    type Cell: Copy + Send + Sync;   // gas: moles + energy; heat: energy + capacity
    type Edge: Copy;                 // conductance, aperture, blocked state
    type Flux: Copy + Neg;
    fn flux(a: &Self::Cell, b: &Self::Cell, e: Self::Edge, dt: Seconds) -> Self::Flux;
    fn apply(cell: &mut Self::Cell, f: Self::Flux);
    fn local(cell: &mut Self::Cell, dt: Seconds, out: &mut Effects);     // reactions, sources
    fn settled(a: &Self::Cell, b: &Self::Cell) -> bool;                 // the edge may sleep
    fn max_dt(a: &Self::Cell, b: &Self::Cell, e: Self::Edge) -> Seconds; // stability bound
}
```

The framework provides:
- **Active cells and edges.** An edge sleeps once `settled` is true. A changed cell wakes its neighbours, and a DM command wakes the cell it touches. Today's urgent, fresh and frontier lanes and the adaptive budget become generic.
- **Sub-stepping.** Each step is split into sub-steps from `max_dt`, the stability bound.
- **Conservation by construction.** Each edge's flux is computed once and applied as + on one side and − on the other.
- **Boundary reservoirs.** Immutable cells act as infinite reservoirs: space, and each planet's atmosphere. Space turfs share one reservoir cell.
- **Couplings** between two fields in the same cell, such as gas and solid heat. Each exchange is computed once and applied to both fields.
- **Per-tile effects** as sparse layers with lifetimes: hotspots, smoke, foam, contamination. Their visuals reach DM as VisualChange events.
- **Neighbours** through the grid's per-layer blocked-direction masks. Each field names the layer it uses (air, heat, …).
- **Channels** extracted per cell for watches.
- **Plumbing:** commands, copy-on-write views, telemetry and replay ([rust_core.md](rust_core.md)).

A new field (smoke, a reagent cloud, radiation contamination) is just a cell type and a flux.

## 2. Propagation services

These run on the grid, with one implementation each:
- **Wavefront.** A costed flood, using Dijkstra or BFS over block layers. Uses: pathfinding flow fields, sound blocked by walls, EMP falloff, explosion reach if it's ever needed.
- **Rays.** Attenuation along a line through a shielding layer, used for radiation.

## 3. Network framework

```rust
pub trait NetworkKind {
    type Region;                                                        // the pooled payload
    fn split(r: &Self::Region, weights: &[f32]) -> Vec<Self::Region>;   // must conserve
    fn merge(rs: &[&Self::Region]) -> Self::Region;
    fn step(r: &mut Self::Region, members: &Members, dt: Seconds, out: &mut Effects) {}
}
```

The framework provides:
- **Topology:** ports, edges and dirty sets.
- **Incremental updates:** adding merges regions; removing re-floods, but only within the affected component.
- **Stable region IDs.**
- **Region channels** for watches.
- **Publication**, commands and replay.

It generalizes today's `PipeTopology`.

| Kind | Region payload | Step |
|---|---|---|
| Pipes | Gas (moles and energy) | Devices move gas between regions and turfs (§5) |
| Heat-exchange pipes | Heat (energy and capacity) | Exchange with turfs and space |
| Cables | Power ledger | Settles supply and demand (§6); material power's voltage solver as an optional detailed step |
| Disposals | Routing table | Path and travel time per holder |
| Signal and data networks | Reachability | Which nodes can hear which |
| Conveyor chains | Order | Where items move next |

## 4. Gas (M1)

**What remains specific to gas** is about 2,000–2,500 lines, down from about 9,000:
- the gas registry, mixture maths and heat capacity;
- the flux, including the exponential aperture/volume model for decompression;
- reactions, as `local`;
- planet boundaries.

**Adjacency from DM block masks**
- Each atom that blocks air (windows, doors, firedoors, walls) declares an air-block direction mask.
- A turf's mask is the OR of its own mask and those of its atoms.
- A change, such as a door opening, sends one command.
- Rust builds adjacency from these masks, which replaces calling `CanAtmosPass` to build adjacency.
- DM's `atmos_adjacent_turfs` lists are deleted: that removes 445K per-turf lists and 13 s of boot. The few DM callers that need neighbours ask Rust.

**Reads, scratch values and IDs**
- DM reads through batched calls.
- Temporary mixtures become scratch values ([rust_core.md §3.5](rust_core.md#35-scratch-values)).
- Gas IDs are generated integers.

**Pipes** move to the network framework, and pipe mixtures are region payloads.

**Deleted:**
- the per-slot locks, `GAS_MUTATION_GATE` and `GAS_PUBLICATION`;
- `TurfGases` and `MIX_TO_TURF`;
- the per-cell closure callbacks;
- the dead modules (fixes.md DEAD1);
- the DM routes that the generated bindings replace.

**Validation before switching over**
- Run atmos_idle and atmos_large against the old engine and compare pressures, temperatures and compositions per region within a tolerance.
- The conservation property tests must pass.
- Boot Atmos time, Air time, FFI calls and memory are compared against F1.

## 5. Atmos devices (M2)

A device becomes an **edge** between two mixtures: a pipe region and a turf, or two pipe regions. Each edge has a flow law, parameters and a power draw. Rust integrates all device flows inside the gas step, conserving mass and energy.

| Device | Flow law | Parameters |
|---|---|---|
| Pump | Moves gas towards a target output pressure, limited by power: work ≈ nRT ln(P2/P1) | Target pressure, power rating |
| Volume pump | A fixed volume per second | Rate |
| Passive gate | Flows while input exceeds output plus a threshold | Target |
| Valve and shutoff valve | Equalizes through an aperture while open | Open or closed |
| Vent pump | Pumps between a region and a turf within internal and external pressure bounds | Mode, bounds |
| Scrubber | Removes a filter set at a rate, or siphons | Filter mask, rate, mode |
| Injector | Injects a volume at a rate | Rate |
| Filter, mixer | Splits by gas, or mixes by ratio | Gas, ratios |
| Heat exchanger | Exchanges energy between two mixtures | Conductance |
| Connector | Hands a canister's mixture over to the region while connected | — |
| Canister and tank release | A pressure regulator | Release pressure |

**What DM keeps**
- Settings go to Rust as commands. The UI reads values from the pinned view.
- Wires, hacking and construction stay in DM.
- Events come back: stalled, target reached, filter saturated.
- Power draw is published to the power domain.

**Air alarms** become `Band` watches, one band per gas and per pressure and temperature limit. DM hears "level changed", and the 463 alarms stop polling and lose their per-instance lists.

**Firedoors** become `Difference` watches on the pressure and temperature across the door. The 2,070 doors lose their snapshot lists.

**Deleted:**
- device `process()` procs;
- `hibernate_vent` and the other hibernate helpers;
- `queue_pump_transfer`/`flush_pump_transfers`;
- the double vent subscription (turf plus network, where one network change scans every vent on it).

## 6. Power (M3)

**Regions and loads**
- Cables become a network kind, and each region holds a **ledger**: supplies, demand by class (equipment, lighting, environment), and storage.
- Machines register static loads once and send changes as deltas, which is what DM does today, moved into Rust.
- One-off draws are commands.

**Storage** (APC cells, SMES, batteries, and borg cells with the body rewrite) uses **rate models**:
- charge is linear between events;
- Rust predicts empty, full, brownout and restore, and emits them as events.

APCs (38 awake) and SMES (23 awake) are the largest always-awake groups today, and this lets them sleep.

**Generators** are supplies:
- PACMAN is a supply.
- Solar changes only when the sun moves, which is an event.
- The TEG reads gas temperatures from the gas view, so it couples through the exchange buffer.

**Events to DM**
- One event per area channel change. DM then sends the machinery power-lost and power-restored signals (defined today but never sent) to that area's subscribers, instead of scanning the whole area.
- Brownout and restore per region, for monitors.

**Topology**
- An explosion becomes one batched topology commit. `makepowernets()` no longer runs after every explosion.
- Cable edits wake only the regions they affect. The fan-out to every sleeping APC and the quadratic `worklist |=` go away.

**Material power.** The CG voltage solver in `material_power.rs` becomes the optional detailed step for circuits that need voltages, moved with its owner's agreement.

**Deleted:**
- `/datum/powernet`'s topology jobs, `propagate_network`, `merge_powernets` and `makepowernets()`;
- accounting windows;
- `publish_apc_supply_changes`;
- the stale-supply checks in the machine loop.

## 7. Heat (M4)

**Heat nodes**
- **Turf solids** form a field on the grid, whose cells carry energy, heat capacity and conductance from materials. They couple to turf gas.
- **Heat bodies** are objects, machines, mobs and containers.
  - A body gets a node only when it moves away from ambient temperature; items follow their surroundings by default.
  - A body's heat capacity includes the latent contents of a container ([containment.md](containment.md)).
- **Heat-exchange pipe regions** are a network kind.

**Couplings**
- Body to environment: turf air, or a container's interior.
- Worn insulation, as thermal resistances in series from the equipment slots.
- Contact: a held item, a buckled mob.
- Machines as sources and sinks, in watts.
- Radiation to space: Stefan–Boltzmann, which is commented out today.

**Exact solutions**
- A body coupled to a large reservoir relaxes as `T(t) = Ta + (T0 − Ta)·e^(−t·G/C)`, so there are no steps while conditions hold.
- Crossing times are solved and scheduled.
- A change in the reservoir past its hysteresis starts the model again from the current value.

**Thresholds**
- `ThresholdSet` watches cover melting, ignition, cooking, reaction temperatures and comfort bands. Containers hold one set covering their latent contents.
- **Thermal regulator primitive:** a target temperature, a maximum power scaled by part rating, and a heat pump limited by its coefficient of performance that dumps rejected heat on the hot side. Heaters, freezers, space heaters, cryo, thermomachines, suit coolers and rig cooling all use it ([temperature.md](temperature.md)).
- **Materials** supply heat capacity, conductance and thresholds. Fixing the conductance scale (B8) makes wall materials matter.

**What it absorbs**
- `material_service`'s heat model: `add_heat` with a phase buffer, exponential exchange, and scheduling on a heap.
- The separate models: humans, simple mobs, cookers, bunsen burners, distilleries, HE pipes and cryo.

**Deleted:** `superconduct.rs`, and every DM copy of the share formula (`datum_pipeline.dm`, `generator.dm`, `heat_exchanger.dm`, `cryo.dm`, `he_pipes.dm`).

## 8. Propagation users (M5)

- **Radiation.** Rays through a shielding layer on the grid. The insulation cache follows the grid's revision, so the 1-second expiry that always misses (B15) is gone.
- **EMP.** Falloff by wavefront. It plays one sound per listener, not one per mob.
- **Later:** pathfinding flow fields for many mobs heading to the same goal, if expedition mob counts grow.

## 9. Generation (M6)

The remaining generated-station planners move next to `station_layout` in `vg-layout`: utility routing, light spacing, hull validation, and the `"x,y"` tile-plan datums. Today they make 25.6M `tile_key` calls and cause ticks at 292–1,072% of budget. They run as jobs, and DM applies the results in budgeted batches.

Delete the DM room solver (DEAD2) and the DM planner duplicates.

## 10. Later candidates (M7)

Each of these is a separate proposal with benchmarks. None starts before M1–M4.

- **Lighting corner sums.** Southern Cross has 62,191 corners, 29,904 lighting objects and 12,733 sources. It is feasible, but the results must match BYOND's `view()` rules. Underlay updates stay in DM.
- **Infrastructure as data.** Under-floor cables and pipes, about 17K movables, stop being atoms until the floor is opened. This cuts memory, atom init and SendMaps work. It depends on M2 and M3.
- **Pathfinding in Rust**, if caching failed searches (Q9) isn't enough.
- **Latent z-levels.** Mostly empty z-levels and released expedition sites load and unload as templates.

## 11. What stays in DM, and why

| System | Why |
|---|---|
| Explosion propagation | Under 5% of explosion cost. The rest is `ex_act` side effects, which the damage pipeline batches (D5). |
| Disposals, conveyors, cameranet | 0.2–0.5 s per 3 hours |
| Reagent chemistry | Reactions are DM behaviour; reagent holders only gain heat capacity (H3) |
| Body model, UI, interactions | Rules and presentation, not simulation |
