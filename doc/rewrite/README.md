# DeepQuarry rewrite

This folder describes the architecture DeepQuarry is moving to and the plan for getting there. Instead of fixing systems one at a time, everything migrates onto a few shared systems:
- one Rust simulation core
- one scheduler
- one containment system
- one engine for properties, rules and constraints
- one interaction model
- one damage pipeline
- one thermal model

It is based on seven code surveys and the profiles on disk (August–September 2026). File references were correct when this was written.

## Goals

- **CPU.** DM does nothing unless something changed or a deadline arrived. In a 3.2-hour round with one player, the two biggest DM costs were machines (270 s) and timers (138 s). Both should fall to the work that is actually happening.
- **Memory.**
  - No sub-object exists until something needs it.
  - Shared definitions replace per-instance copies.
  - DM stops duplicating state that Rust already owns.
  - Both the boot peak and the steady-state heap fall. Targets are set from the phase 0 baseline.
- **Correctness by construction.**
  - Mass, energy, charge and items are conserved, and tests prove it.
  - Every concern has exactly one pipeline.
  - State and triggers are declared per type, so nothing can forget to register them.
- **Players.** Every interaction can be listed, can say why it isn't available, and can be bound to a key.

## Principles

1. **State lives where it is computed.** Simulation state lives in Rust: gas, heat, charge, flows, networks and the grid. DM holds handles to it and owns rules, behaviour and UI.
2. **Nothing runs without a change or a deadline.** A continuous process becomes a rate with predicted events.
3. **Types define; instances store differences.** A sub-object stays as data until something needs a real object.
4. **Declare, don't register.** The framework reads type data for slots, properties, rules, constraints, interactions and behaviours.
5. **One writer per piece of state**, in DM and in Rust.
6. **Conservation and parity are tested, not assumed.**
7. **Everything is measured.** Every step has a benchmark gate.
8. **No shims.** Each wave converts every caller and deletes what it replaces. The body rewrite follows the same rule (`doc/refactor_brief.md`).

## Layers

```
DM    SSreactor · Ledger & slots · Rules & constraints · Interactions · Damage pipeline · Thermal API
          │ commands in, one batched event drain per tick      ▲ generated bindings
Rust  vg-ffi ──────────────────────────────────────────────────┘
      domains:  gas · atmos devices · power · heat · propagation · generation
      vg-core:  owners & frames · handles · stores & grid · channels & watches · timers & rate models
                fields · networks · outbox · jobs · metrics
```

## Documents

| Document | Covers |
|---|---|
| [roadmap.md](roadmap.md) | Tracks, work items, dependencies, waves, gates and guardrails |
| [fixes.md](fixes.md) | Bugs, quick wins, low-risk memory savings and dead code to handle first |
| [rust_core.md](rust_core.md) | `vg-core`: threading, handles, stores, grid, watches, timers, the DM bridge, jobs, metrics and testing |
| [simulation.md](simulation.md) | The field and network frameworks; gas, atmos devices, power, heat, propagation and generation |
| [reactor.md](reactor.md) | SSreactor: the DM side of events, timers and continuous work |
| [state.md](state.md) | State schema, serialization, deltas, lifecycle, registries and signals |
| [rules.md](rules.md) | Properties, predicates, constraints, rules and abilities |
| [containment.md](containment.md) | Ledger, slots, latent contents, equipment, inventory, storage, vore and occupants |
| [interactions.md](interactions.md) | Input actions, keybinds, interactions, tools and construction |
| [damage.md](damage.md) | Damage packets, mitigation, where damage lands, and thresholds |
| [temperature.md](temperature.md) | One thermal model covering Rust, mobs, items, reagents and machines |
| [object_model.md](object_model.md) | Object kinds, ownership, relations, archetypes, behaviours, requirements, events, scheduling, tasks, UI and dm-health (authoritative) |
| [object_model_core.md](object_model_core.md) | The object-model core API: scheduler, change tracking, derived values, relations, contributions, rates, events, checks, tasks, UI and the table-first declarations (authoritative; supersedes the API parts of object_model.md) |
| [lifecycle.md](lifecycle.md) | Destruction as a framework transaction: phases, slot policies and verbs |
| [rust_architecture.md](rust_architecture.md) | Verdigris: domains as declarations plus laws, the generic core, crate map and plan (authoritative) |

## How the work runs

- The work is split into tracks and delivered in waves ([roadmap.md](roadmap.md)). Every wave:
  - compiles clean and keeps the suite green: `tools/build/build.sh dm-test`, plus `cargo test` in `verdigris/` for Rust changes;
  - deletes what it replaces;
  - adds its lint rules and a changelog entry;
  - keeps and extends debug logging;
  - records benchmarks before and after with `tools/build/build.sh bench --runs=3`, compared using `bench-compare`.
- Agents work in slices and follow `AGENTS.md` and the build lock.
- If another agent's work in progress leaves the tree uncompilable, `DQ_WIP_TREE=1` makes validation and test builds skip unreachable files (see `doc/testing.md`).
- A design change updates these documents in the same change as the code.

## Coordination with the body rewrite

The medical and body rewrite is described in `doc/mob_life_architecture.md` (§8), `doc/health_system_review.md` and `doc/body_architecture.md`. Another session owns it, and it runs in parallel with this one. It owns:
- `injure()` and `mend()`;
- body plans, afflictions, organs and surgery;
- species and proteans;
- the mob `Life()` systems;
- material prices and `material_power.rs`.

These interfaces need agreeing with it before either side builds on them:

| Interface | This rewrite provides | The body rewrite provides |
|---|---|---|
| Scheduling | Reactor watches, timers and rate models. These replace `subscribe_gas_dependency` and `publish_reactive_dependency`, which its life systems currently plan to use. | Life systems register through the reactor, and mob hibernation wakes through it |
| Damage | The damage packet, mitigation and entry-point adapters | The `injure()` kinds each packet kind maps to |
| Equipment | Body-part slots, layers, and per-zone aggregates such as armour and insulation | Which body parts carry which slots, and equipment factors |
| Temperature | A body heat node in Rust, coupled to the environment and to clothing | Thermo strategies (endotherm, ectotherm, …), thresholds and their effects |
| Power | The power domain's ledger and rate models | Robot power demand (its phase 7 "power ledger"), built on these |
| Mechs | Pilot, hardpoint and cargo slots | A body host interface so an object can own a body. Today `/datum/body` is owned by `/mob/living` (`code/modules/body/body.dm:41`). |
| Abilities | The ability framework ([rules.md](rules.md)) | The protean powers registry, built on it |
| Occupants | Occupant slots with sealed environments | Sleeper, scanner and cryo behaviour, after its phases land |

## Evidence baseline

All figures come from what is on disk today. Phase 0 re-measures them with the benchmark suite.

| Area | Measured | Main causes |
|---|---|---|
| DM CPU (3.2 h, 1 player) | Machines 270 s, Timer 138 s, Statpanels 70 s, Garbage 62 s, Air 52 s, Lighting 26 s, Radiation 22 s, Mobs 18 s | 200–420 machines always awake, mostly APCs and SMES; looping sounds with nobody listening (62 s, plus 1.9M timer inserts); the MC tab re-sorting samples (26.5 s); 428 hard deletes at about 140 ms each |
| Engine | SendMaps 151 s, examining 245M movables | Movables on visible turfs |
| Boot (122–158 s) | Atoms 38–60 s, Atmos 45–61 s, Assets 18–25 s, Lighting 7–9 s | Sub-objects created eagerly; 445K per-turf DM adjacency lists that copy Rust's data; 858 tgui chunks hashed through temp files when only 416 are used |
| Memory (atmos soak runs) | Peak 2.24–2.35 GB during boot, about 1.6 GB steady, of which Rust holds about 230 MB | Tens of thousands of eager atoms, about 75k avoidable lists, per-turf lists |
| Calls from DM into Rust | 25M gas calls in the 3-hour round | One call per field read; 1.5M temporary mixtures; gas IDs sent as strings; `get_gases` making N+1 calls |
| Structure | 9 scheduling mechanisms, about 7 temperature models, about 15 separate health pools, about a dozen container systems | Everything is handled type by type |

## What "done" means

- Every guardrail in [roadmap.md](roadmap.md) is enforced in CI.
- No DM `process()` runs unless it is declared continuous, and every wake has a recorded reason.
- There is no `call_ext` outside the generated bindings, and DM keeps no copies of Rust state.
- The conservation, parity and rule tests pass for every type they apply to.
- The benchmarks meet the targets set after phase 0.
