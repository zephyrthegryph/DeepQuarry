# Rewrite roadmap

This roadmap covers every work item, what each depends on, and what "done" means. The design behind each track is in its own document. Item IDs are stable, so refer to them in reports, commits and changelogs.

## Rules for every item

- **Wholesale.** Convert every caller and delete what the item replaces in the same change. No shims, and no commented-out code.
- **Green.** Compile clean. `tools/build/build.sh dm-test` stays green, and so does `cargo test` in `verdigris/` for Rust.
- **Measured.** Record benchmarks before and after with `tools/build/build.sh bench --runs=3`, compare them with `bench-compare`, and put the numbers in the report.
- **Enforced.** Add the item's lint rules (see [Guardrails](#guardrails)) and a changelog entry.
- **Logged.** Keep existing debug logging, and add logging for anything new.
- **Documented.** Update the design document when the design changes.

The lead compiles and runs the suite between waves, and agents stay inside their slice (`AGENTS.md`, `doc/refactor_brief.md`). Items marked "with the body rewrite" need the interface in [README.md](README.md#coordination-with-the-body-rewrite) agreed before work starts.

## Tracks

| Track | Scope | Design |
|---|---|---|
| **F** | Fixes, quick wins, baseline | [fixes.md](fixes.md) |
| **R** | Rust core | [rust_core.md](rust_core.md) |
| **M** | Simulation domains | [simulation.md](simulation.md) |
| **S** | Scheduling (SSreactor) | [reactor.md](reactor.md) |
| **L** | State and lifecycle | [state.md](state.md) |
| **P** | Properties, rules, constraints, abilities | [rules.md](rules.md) |
| **C** | Containment | [containment.md](containment.md) |
| **I** | Interactions and input | [interactions.md](interactions.md) |
| **D** | Damage | [damage.md](damage.md) |
| **H** | Temperature (DM integration) | [temperature.md](temperature.md) |

## Work items

### F: fixes and baseline

| ID | Work | Needs | Done when |
|---|---|---|---|
| F1 | Get the tree compiling. Run `bench --runs=3` on the test map and with `-DCITESTING_FULL_MAP` for boot_memory, idle, atmos_idle, atmos_large, major_events, generation and sm_soak. Take the first instance census. | — | Runs are stored in `data/bench/`, and the baseline table below is filled in |
| F2 | Correctness bugs ([fixes.md §1](fixes.md#1-correctness-bugs)) | — | Each bug has a regression test |
| F3 | Boot quick wins ([fixes.md §2](fixes.md#2-boot-quick-wins)) | F1 | Assets and total boot time are down against the baseline |
| F4 | Runtime quick wins ([fixes.md §3](fixes.md#3-runtime-quick-wins)) | F1 | Idle DM CPU (Timer, Statpanels, Radiation, Garbage) is down |
| F5 | Low-risk memory ([fixes.md §4](fixes.md#4-low-risk-memory)) | F1 | The boot_memory list count is down, with no behaviour change |
| F6 | Dead code ([fixes.md §5](fixes.md#5-dead-code)) | — | Removed; build and tests green |
| F7 | Hard deletes and runtime spam ([fixes.md §6](fixes.md#6-hard-deletes-and-runtimes)) | F1 | Hard deletes and runtimes per round are down |

### R: Rust core

| ID | Work | Needs | Done when |
|---|---|---|---|
| R1 | Split the workspace into `vg-core`, `vg-ffi`, the domain crates and the `verdigris` DLL. Host-built parallel tests run in CI, with a criterion benchmark harness. | — | `cargo test` passes on x86_64 without `RUST_TEST_THREADS=1`, and the i686 build still works |
| R2 | Primitives: handles (20-bit index plus 4-bit generation), `Arena`, `Grid` (chunked, block layers, bounds-checked), bitsets, interner, units, thermodynamics kernel, RNG streams, tagged allocator | R1 | Property tests pass, including a regression test for the heat edge wrap |
| R3 | The DM bridge: bind macro, generated `_bindings.dm` using cached `load_ext` handles, numeric registries, version handshake. Migrate every call site. | R1 | No hand-written `call_ext` remains, CI fails when bindings are stale, and FFI time per call is down |
| R4 | Owners and frames: per-entity owners, command buffers, copy-on-write views, a view pinned per tick, the overlay, the frame task graph and a dedicated thread pool | R2 | A replay determinism test passes, DM paths take no locks, and the overlay property tests pass |
| R5 | Channels and watches (Changed, Threshold, Band, Difference, ThresholdSet), the outbox, and the main-side timer wheel, wake lanes and rate models | R4 | Every declared channel and condition is validated at boot, and the watch-semantics tests pass |
| R6 | Field framework | R4, R5 | Conservation property tests and reference solutions pass |
| R7 | Network framework, generalizing `PipeTopology` | R4, R5 | Split/merge conserves, and incremental updates match a full rebuild |
| R8 | Propagation services: wavefront and rays | R2 | Reference tests pass |
| R9 | Jobs registry, metrics registry, flight recorder, replay tool | R4 | Station layout runs on jobs, the benchmarks read metrics in one call, and material power moves over with its owner's agreement |

### M: simulation domains

| ID | Work | Needs | Done when |
|---|---|---|---|
| M1a | **Gas groundwork on today's arena**: Rust builds adjacency from DM air-block masks and the DM `atmos_adjacent_turfs` lists are deleted; batched reads; integer gas IDs; delete the old locks, gates and dead modules. | R3 | atmos_idle and atmos_large results match the baseline within tolerance; FFI calls and boot Atmos time are down; the 445K per-turf DM lists are gone |
| M1b | **Gas on the field framework, pipes on the network framework**, through owners, commands, views and the overlay | M1a, R4–R7 | Conservation tests pass, Air time is down, and the old arena, locks and gates are deleted |
| M2 | **Atmos devices** become edges with flow laws. Air alarms become Band watches and firedoors become Difference watches. | M1b, S1 | Device `process()` is deleted, idle Machines time is down, and every flow law has tests |
| M3 | **Power**: cables become a network kind, with a ledger, storage rate models, area channel events and the machinery power signals. Explosions batch their topology changes. | R7, S1 | DM powernet code is deleted, APCs and SMES sleep while idle, and major_events no longer pays for power rebuilds |
| M4 | **Heat**: the turf field, heat bodies, couplings, ThresholdSet and the thermal regulator. Absorbs `material_service`'s thermal model. | R5, R6 | `superconduct.rs` and the DM formula copies are deleted, energy conservation tests pass, and sm_soak is no worse |
| M5 | Propagation users: radiation through rays and an insulation layer; EMP falloff | R8 | Radiation time is down and behaviour tests pass |
| M6 | Move the generation planners into `vg-layout` | R9 | The DM planners and room solver are deleted, and generation tick peaks are down |
| M7 | Later: lighting corners, infrastructure as data, pathfinding flow fields | M1–M4 | Each lands as its own proposal with benchmarks |

### S: scheduling

| ID | Work | Needs | Done when |
|---|---|---|---|
| S1 | SSreactor: wake dispatch, timers, the continuous lane, DM-owned keys and bounded metrics | R5 | The profiler and the benchmarks report wake reasons, and every API has unit tests |
| S2 | Move the SSmachines reactive keys, the non-device gas subscriptions and SSai's chunk hibernation onto the reactor, and delete their tables and helpers | S1, M1b | The `machines.dm` dependency code is deleted, and every former subscriber has a wake test |
| S3 | Convert the pollers: airlocks, cameras, lights, status displays, looping sounds, shutoff valves and mob chunk keys | S1 | Idle Machines plus Timer time is down, and the deadline-polling lint is on |
| S4 | Retire SSobj, SSprocessing, the SSfastprocess users, SSbellies, SSburning, SSmaterial_services and the heavy SStimer users | S3, C7, M4 | `START_PROCESSING` is gone outside the reactor, and every remaining continuous user is declared |
| S5 | Machines start asleep, and `START_MACHINE_PROCESSING` is removed | S3, M2, M3 | The 200–420 always-awake machines fall to those actually working |

### L: state and lifecycle

| ID | Work | Needs | Done when |
|---|---|---|---|
| L1 | State schema: `tmp` hygiene, a lint for reference vars, codecs, canonical deltas, versioning and the serializer. Migrate the vore serializer onto it. | — | Round-trip tests pass for every latent-safe type, and the lint runs in CI |
| L2 | Split the lifecycle into `Initialize()` and `on_materialize()`/`on_dematerialize()` | L1 | The sandbox side-effect test passes for every latent-safe type |
| L3 | Registries replace ad-hoc global lists | L2 | `Initialize()` no longer writes global lists, and hard deletes are down |
| L4 | Signals: declared argument counts, an audit of what is sent and listened for, pooled dispatch, type elements and listen masks | — | The audit runs in CI, and dead signals are deleted or wired up |

### P: properties, rules, constraints, abilities

| ID | Work | Needs | Done when |
|---|---|---|---|
| P1 | Property registry: per-type properties from `initial()` and variants, tags, measures, providers and aggregators | L1 | Boot validation passes |
| P2 | Predicate language, with units and reasons | P1 | Predicate tests pass |
| P3 | Constraints replace `can_hold`, `cant_hold`, `allowed`, `species_restricted`, the `slot_flags` checks, `mob_can_equip` and `can_be_inserted` | P2, C1 | Those vars and procs are deleted, and equip and insert parity tests pass |
| P4 | Rules compile to reactor watches, with data-transform and behaviour effects and generated rule tests | P2, R5 | Every declared threshold has a rule test |
| P5 | Abilities: Shadekin phase shift first, then species and borg abilities, then protean powers (with the body rewrite) | P3, P4, I2 | Phase shift is ported without its energy-loss bug, and abilities can be listed and bound to keys |

### C: containment

| ID | Work | Needs | Done when |
|---|---|---|---|
| C1 | Ledger and slots: move transactions, drop policies in the base `Destroy()`, entry IDs and aggregates | L1, P1 | A conservation fuzz test passes for every holder type, and the lint for raw `loc` and `contents` writes is on |
| C2 | Exposure, layers and propagation paths | C1 | Heat and damage path tests pass |
| C3 | Inventory and equipment on body-part slots; pickup, drop, throw and equip interactions; robot modules (with the body rewrite) | C1, I2 | The per-slot vars, the `u_equip` chains and `equip_to_slot`'s direct `loc` writes are deleted |
| C4 | Storage on slots, with screen objects created per viewer | C1, P3 | The `/obj/item/storage` insertion code is deleted, and the 6–8k screen atoms are gone |
| C5 | Latent contents: generators, entries, resolve, materialize and collapse, with parity tests. Roll out to closets, then mapped storage, lights, ammo, pills, and finally radios, headsets and ID cards (PDAs need on_materialize()-time app construction first; see containment.md section 4.6). | L2, L3, C1, P4 | Each rollout step reduces boot_memory atoms, and parity tests pass |
| C6 | Machine internals become data: part tiers, and boards as paths | C1, I5 | Eager `component_parts` and eager circuit boards are gone |
| C7 | Vore on slots: a sealed interior, modes as rules and rate models, consent as requirements, shared message lists | C1, P4, S1, D1 | SSbellies is deleted, and empty bellies cost nothing |
| C8a | Occupant and mech containment: sealed occupant slots, mech pilot, hardpoint and cargo slots, and blast shares. Medical machines (cryo, sleepers, scanners) wait for the body rewrite's automation work | C2, D5 | The duplicated go-in, go-out and eject code is deleted |
| C8b | Mech damage through the body model. The body rewrite provides the body host interface; it also owns occupant behaviour in medical machines | C8a, D3 | Mech damage goes through `injure()` |
| C9 | Vending and smartfridge stock become stock slots | C1 | Vending no longer materializes a product's whole amount at once |
| C10 | Latency policy: an atom is latent when its slot is not rendered or interactive, nobody views the holder, it has no timers, processing, signals, outside refs or live weakrefs, its type is verified storable, and it has been idle past a delay. A budgeted reactor sweep collapses, events materialize. The sandbox CI verifies storability per type instead of the hand-kept `latent_safe` list. Test and dev builds run a round-trip audit, and a config kill switch turns collapse off | C5, C6, S1 | `latent_contents` and `latent_safe_types.dm` are gone; the fuzz and round-trip audits pass |
| C11 | No raw contents access: every holder access goes through the ledger API, and tile queries go through a spatial API (`in T`, `locate() in T`). A lint caps raw uses and the count only goes down | C1, I7 | The raw-access count reaches 0 outside the ledger and spatial API |

### I: interactions and input

| ID | Work | Needs | Done when |
|---|---|---|---|
| I1 | Input layer: actions, bindings, keybind preferences, per-client macros, one router, right-click and hover | — | The `skin.dmf` macro sets are replaced, and the three modifier ladders are deleted |
| I2 | Interaction framework: definitions, resolver, the Menu action, generated examine text and screentips, categories | P2, I1 | `description_info` strings are deleted as types convert, and interaction snapshot tests pass |
| I3 | Actor adapters for AI, borgs, ghosts and telekinesis | I2 | The forwarding `attack_ai`, `attack_robot` and `attack_ghost` overrides are deleted |
| I4 | Tool pipeline: `use_tool()`, and migrating the `*_act` procs | I2 | Handlers no longer bounce back into `attackby`, and the tool `do_after` sites are converted |
| I5 | Construction graphs | I4 | The `focused_tool_stage` ladders are deleted |
| I6 | Combat mode replaces intents | I2 | The `a_intent` gates are converted |
| I7 | Convert `attackby`, `attack_hand`, `attack_self`, `click_alt` and object verbs one domain at a time | I2–I4 | The legacy procs are deleted in each domain as it converts |

### D: damage

| ID | Work | Needs | Done when |
|---|---|---|---|
| D1 | The damage packet, and adapters for every entry point | P1 | The per-type conversion boilerplate is deleted, and each entry point has a test |
| D2 | Interned armour, deterministic mitigation, shields, equipment zones and material response | D1, C3 | Per-type armour lists are replaced, and mitigation tests pass |
| D3 | Every object uses integrity, including walls and the roughly 15 separate health pools. Map packet kinds to `injure()`. Mechs move onto the body model (with the body rewrite). | D1 | The separate HP vars are deleted |
| D4 | Declarative thresholds, a base machinery break, drop policies and generated flavour text | D3, C1, P4 | The copies of `atom_break` and `set_broken` are deleted |
| D5 | Batched explosions and EMPs | D1 | The `ex_act` severity ladders are deleted, and major_events is faster |

### H: temperature

| ID | Work | Needs | Done when |
|---|---|---|---|
| H1 | DM thermal API and generated constants | M4 | The ad-hoc `return_temperature` variants and duplicate constants are deleted |
| H2 | Mobs: body heat node, a `bodytemperature` setter, and clothing through slots (with the body rewrite's thermo strategies) | H1, C3 | No code writes `bodytemperature` directly, and clothing is no longer scanned every `Life()` |
| H3 | Items, reagents, fire and burning | H1, P4, D1 | The `fire_act` variants are converted, and burning runs through rules |
| H4 | Thermal regulator for machines | H1, M2 | The per-machine heat formulas are deleted, and energy is conserved |

## Waves

Items in the same wave can run in parallel, and every dependency sits in an earlier wave.

| Wave | Items |
|---|---|
| 0 | F1–F7, L4, R1 |
| 1 | R2, R3, L1, P1, I1, D1 |
| 2 | R4, R5, P2, L2, C1, M1a |
| 3 | R6, R7, R8, R9, S1, P3, P4, L3, C2, I2, D5 |
| 4 | M1b, M6, S3, C3, C4, C9, I3, I4, I6, D3 |
| 5 | M2, M3, M4, M5, S2, C5, P5, I5, D2, D4 |
| 6 | H1, S5, C6, C7, I7 |
| 7 | H2, H3, H4, S4, C8 |
| 8 | M7, then final guardrails and cleanup |

The critical path runs R1 → R2 → R4 → R5 → R6/R7 → M1b → M2/M3/M4 → H. The DM tracks (I, L, P, C, D) do not wait for Rust until they need watches (P4) or heat (H).

## Benchmark gates

| Track | Scenarios |
|---|---|
| F | All of them (baseline) |
| R, M1 | atmos_idle, atmos_large, boot_memory, idle |
| M2, S | idle, atmos_idle |
| M3 | idle, major_events |
| M4, H | sm_soak, atmos_large |
| C, L | boot_memory, with the census |
| D | major_events, sm_soak |
| I, P | idle, plus the interaction snapshot tests |

Targets are filled in after F1. Every row compares against the F1 baseline, and each target is written down before the item starts.

| Metric | Baseline (F1) | Target |
|---|---|---|
| Idle DM CPU: Machines + Timer (per hour) | | |
| Boot time: total / Atoms / Atmos / Assets | | |
| Boot peak and steady private memory | | |
| Rust heap (by tag) | | |
| Atom and list census | | |
| Gas FFI calls per second | | |
| Hard deletes and runtimes per round | | |

## Guardrails

These are CI lint rules. Each one comes on when the item that makes it possible lands, and stays on from then.

| Rule | On after |
|---|---|
| No `call_ext` outside the generated bindings | R3 |
| No DM copies of Rust state (`atmos_adjacent_turfs` and similar) | M1a |
| No `var/list/x = list()` initializers on high-count types | F5 |
| No deadline polling (comparing against `world.time`) inside `process()` | S3 |
| No `START_PROCESSING`/`STOP_PROCESSING` outside the reactor, and no undeclared `process()` | S4, S5 |
| No raw `loc =`, `contents +=` or `contents -=` on movables | C1 |
| No raw walks over `contents` on holders with latent contents | C5 |
| Vars that hold references must be `tmp` or have a codec | L1 |
| No global list writes or global signal registration in `Initialize()` of latent-safe types | L2 |
| Every `COMSIG_*` is both sent and listened for, and every signal declares its argument count | L4 |
| No `can_hold`, `allowed`, `species_restricted` or `max_w_class` type lists | P3 |
| No `take_damage` or `injure()` outside the pipeline adapters | D1, D3 |
| No forwarding `attack_ai`/`attack_robot`/`attack_ghost` overrides | I3 |
| No `*_act` that calls `attackby` | I4 |
| No direct `bodytemperature` writes | H2 |
| No raw heat-exchange formulas in DM | H4 |

## Risks

| Risk | Mitigation |
|---|---|
| The overlay and command model (R4) turns out too complex | Prove it on gas in M1 first. The fallback is applying deltas on the main thread within a budget ([rust_core.md §3.11](rust_core.md#311-fallback)). |
| Rust memory grows in the 32-bit process | Per-domain memory tags and budgets, with alerts in the benchmarks |
| Latent contents behave differently from real ones, because about 590 legacy `contents` loops don't see latent entries | Opt in per holder type, parity tests, and a lint for raw walks |
| Conflicts with the body rewrite | Agree the interfaces first, keep to slices, and let the lead integrate between waves |
| Players dislike the new controls (right-click Menu, keybinds) | Default bindings reproduce today's controls. Review with players before switching defaults. |
| Scope creep | Items are fixed and time-boxed. New ideas go into the design documents as proposals, not into running items. |
