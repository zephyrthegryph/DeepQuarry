# DeepQuarry rewrite: index and reading order

**Primary design: [final_api.html](final_api.html)** (open in a browser). It is the approved final
API and migration plan (1 October 2026) and supersedes every document below where they disagree.
Section 17 maps each old form to its replacement, section 19 is the migration plan, section 22 the
source layout. `../../AGENTS.md` summarises it for day-to-day work. The rest of this folder is
background and detail: the foundation design that fed into it, and the archived OM docs.

This folder describes the architecture DeepQuarry is moving to and the plan for getting there.
The current design is the **foundation design**: three table procs per type (`capabilities()`,
`relations()`, `reactions()`), one reactive change graph, operations and actions for player input,
a kernel host loop, and one Rust frame. It replaces the earlier object-model (OM) API; the old
docs are kept in [archive/](archive/) with a header saying what replaced each.

Status legend used throughout: **[built]** merged on `rewrite/dx-framework`; **[in progress]**
being built on a branch below; **[planned]** designed, not written. Don't invent a [planned] API.

## Reading order

1. [foundation.md](foundation.md): the design overview and the vocabulary table.
2. [state_and_relations.md](state_and_relations.md): tracked state, generated reads, relation kinds.
3. [reactions.md](reactions.md): the one reaction mechanism, notices, timers.
4. [operations_and_actions.md](operations_and_actions.md): requirements, affordances, routes, operations, actions.
5. [look.md](look.md), [construction.md](construction.md), [pools.md](pools.md): appearance, ladders, flyweights.
6. [scheduling_and_kernel.md](scheduling_and_kernel.md): systems, work, membership, `kernel_tick`.
7. [rust.md](rust.md): `vg_frame`, the outbox, `native_read`, no mirrors.
8. [dx_conventions.md](dx_conventions.md) (the rules) and [migration_guide.md](migration_guide.md) (old form to new form, Part F first).

## Branch status of the foundation batch

Base `rewrite/dx-framework`. Old call sites are not migrated by this batch; new APIs are added
beside the old forms.

| Branch | Owner | Builds | Status |
|---|---|---|---|
| `rewrite/f-reactions` | W1 | TRACKED demand-gating, `reactions()`, triggers, `observe`, notices, relation kinds, `after` | [in progress] |
| `rewrite/f-ops` | W2 | `req`, `cap_require`, `cap_op`, `refine`, affordances, routes, compartments, actions, bind profiles | [in progress] |
| `rewrite/f-look` | W3 | `look.variant/part/glow`, construction primitives and joints, pools, rename tool | [in progress] |
| `rewrite/f-rust` | W4 | `vg_frame`, outbox, `native_read`, one watch facility, mirror deletion, gas binds | [in progress] |
| `rewrite/f-kernel` | W5 | `kernel_tick`, phases, urgent requests, membership as relations, systems | [in progress] |
| `rewrite/foundation` | W6 | Integration; rebuilds the APC in the target shape; full suite | [built] |
| `rewrite/f-docs` | - | This documentation set | this branch |

## Document map

### Current: the foundation set

| Document | Covers |
|---|---|
| [framework_gaps.md](framework_gaps.md) | Open framework gaps and what is missing from the design |
| [foundation.md](foundation.md) | Overview, vocabulary, design rules, the target APC example |
| [state_and_relations.md](state_and_relations.md) | `TRACKED`, `READERS`, generated reads, relation kinds, source counts |
| [reactions.md](reactions.md) | Triggers, static vs dynamic, notices, timers, urgent vs wake |
| [operations_and_actions.md](operations_and_actions.md) | Requirements, affordances, routes, compartments, `cap_op`, actions |
| [look.md](look.md) | `variant`/`part`/`glow`, the icon naming convention, rename tool |
| [construction.md](construction.md) | Primitives, joints, ladder presets, conservation test |
| [pools.md](pools.md) | `/datum/pooled`, reset, poison |
| [scheduling_and_kernel.md](scheduling_and_kernel.md) | `kernel_tick` phases, systems, work, urgent requests |
| [ai_packs.md](ai_packs.md) | AI packs, states and standings (approved 2026-10-06): the engine forms `coalesce()`, `modes()`, `stance()` and the pack, brain and tactic design built on them |
| [life_sequences.md](life_sequences.md) | Sequences (entity-major kernel work: steps as procs, `after` edges, `should_run`, parking as membership), Mob Life's landing spot, the S1-S4 waves |
| [rust.md](rust.md) | `vg_frame`, outbox, watches, no mirrors |
| [dx_conventions.md](dx_conventions.md) | The rules and CI lints |
| [migration_guide.md](migration_guide.md) | The API as built, and every old form with its replacement |
| [roadmap.md](roadmap.md) | Tracks, work items, waves and gates (partly predates the foundation; item IDs are stable) |

### Still-valid domain and detail references

These stay where they are. Where a foundation chapter overrides part of one, the chapter says so.

| Document | Covers | Note |
|---|---|---|
| [damage.md](damage.md) | Damage packets, mitigation, thresholds | Packets become pooled ([pools.md](pools.md)) |
| [temperature.md](temperature.md) | One thermal model | Uses the one watch facility ([rust.md](rust.md)) |
| [containment.md](containment.md) | Ledger, slots, equipment, storage, vore | Edges supply route policy |
| [rules.md](rules.md) | Properties, predicates, constraints, abilities | |
| [lifecycle.md](lifecycle.md) | Destruction as a transaction | Refs are relation kinds |
| [state.md](state.md) | State schema, serialization, registries | Reactive parts: [state_and_relations.md](state_and_relations.md) |
| [caching.md](caching.md) | Shared caches | |
| [simulation.md](simulation.md) | Fields and networks in Rust | |
| [rust_architecture.md](rust_architecture.md), [rust_core.md](rust_core.md), [rust_bindings.md](rust_bindings.md) | The Rust library structure and bindings | Drivers, watches and mirrors overridden by [rust.md](rust.md) |
| [kernel.md](kernel.md) | Detailed kernel design and measurements | Phases and work units overridden by [scheduling_and_kernel.md](scheduling_and_kernel.md) section 6 |
| [init_and_turfs.md](init_and_turfs.md) | Boot and bulk-destroy speed | |
| [agent_workflow.md](agent_workflow.md) | The build/test/merge loop: generated files, merging master | Read before your next merge |
| `doc/body_architecture.md`, `doc/mob_life_architecture.md`, `doc/testing.md` | Body, mob Life, testing | Outside this folder |

### Archive

[archive/](archive/) holds two kinds of file, each with a one-line header.

| Kind | Files |
|---|---|
| **Superseded by the foundation design** (still accurate for code not yet converted) | `object_model.md`, `object_model_core.md`, `om_in_10_minutes.md`, `time_mechanisms.md`, `ownership.md`, `interactions.md`, `systems.md`, `life_on_om.md`, `migration_plan.md`, `declarative_lifecycle.md` |
| **Historical records** (audits, reports, briefs) | `fixes.md`, `framework_fixes.md`, `memory_lists_audit.md`, `om_framework_report.md`, `life_on_om_benchmark.md`, `object_model_medical_review.md`, `reconciliation.md`, `signal_migration_map.md`, `systems_worker_brief.md`, `health_system_review.md` |
| **Design source** | `unified_operations_work.md` (the operations proposal, verbatim) |

Until the f-* branches merge, most code still uses the OM forms, so `AGENTS.md` section 9 points
at the archive copies for those; each such pointer also names the replacing chapter.

## Principles

1. **State lives where it is computed.** Simulation state lives in Rust; DM holds handles and owns
   rules, behaviour and UI.
2. **Nothing runs without a change or a deadline.**
3. **Types define; instances store differences.**
4. **Declare, don't register.** Three table procs, interned per type.
5. **One writer per piece of state**, in DM and in Rust.
6. **Conservation and parity are tested, not assumed.**
7. **Everything is measured.** Every step has a benchmark gate.
8. **No shims.** Each wave converts every caller and deletes what it replaces.

## How the work runs

- The work is delivered in waves ([roadmap.md](roadmap.md)). Every wave compiles clean, keeps the
  suite green (`tools/build/build.sh dm-test`, the normal tier; CI also runs `--tier=all`; plus `cargo test` in `verdigris/` for Rust), deletes
  what it replaces, adds its lint rules and a changelog entry, keeps debug logging, and records
  benchmarks before and after (`tools/build/build.sh bench --runs=3`, `bench-compare`).
- Agents work in slices and follow `AGENTS.md` and the build lock. If another agent's work leaves
  the tree uncompilable, `DQ_WIP_TREE=1` skips unreachable files (see `doc/testing.md`).
- A design change updates these documents in the same change as the code.

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

## Coordination with the body rewrite

The medical and body rewrite is described in `doc/mob_life_architecture.md` (§8), `doc/rewrite/archive/health_system_review.md` and `doc/body_architecture.md`. Another session owns it, and it runs in parallel with this one. It owns:
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
- No DM `process()` runs unless it is declared, and every wake has a recorded reason.
- There is no `call_ext` outside the generated bindings, and DM keeps no copies of Rust state.
- The conservation, parity and rule tests pass for every type they apply to.
- The benchmarks meet the targets set after phase 0.
