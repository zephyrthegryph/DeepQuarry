# Migration plan: ownership, scheduling and the Rust core

Status: **authoritative order and estimates**, as of 2026-09-26. This file owns the *order*; the designs live in:
- [object_model_core.md](object_model_core.md): §4.10 pipelines, §4.11 one scheduler, §7 relations and slots;
- [lifecycle.md](lifecycle.md): destruction as a transaction, and LC-refs;
- [containment.md](containment.md): slots, latent contents;
- [rust_architecture.md](rust_architecture.md) §8: the Rust consolidation;
- [roadmap.md](roadmap.md): item IDs.

## 1. The end state

Every piece of gameplay state and every piece of deferred work has a declared owner.

| Concern | The only mechanism | Gone |
|---|---|---|
| Links between things | relations (accessor macros, no view fields) | hand-kept pairs, back-reference vars, `/datum/weakref` for live links |
| Where things are | slots on the ledger (relations that own `loc`) | raw `loc =` and `contents +=`, per-type go-in/go-out code |
| Remembering who something was | OM handles (id + generation, `om_resolve`) | `/datum/weakref` |
| Any other reference | an owned child, or a declared cache with an invalidation rule | undeclared datum-typed vars and object lists in `GLOB` |
| Later and repeating work | `om_after`, clocks, stage rewakes, timed contributions | SStimer, `addtimer`, `spawn` |
| Multi-step work | `om_task` steps | `do_after`, gameplay `sleep()` |
| Waiting on a player | `om_prompt` callbacks with re-checks | blocking `input`/`alert`/`tgui_input_*` |
| Not blocking a caller | nothing is needed: nothing sleeps | `INVOKE_ASYNC`, `set waitfor`, `stoplag` in gameplay |
| Periodic simulation | pipelines, watches and parking | `process()` and polling subsystems |
| Destruction | the destroy transaction plus declarations; verbs (`consume`, `replace_with`, `expire`, `slot_clear`) | about 85% of `Destroy()` overrides, about half of `qdel` sites, raw `del` |
| Rust domains | declarations and laws on the core World | private engines, stores, handles, event queues and the reactor |

**Bug classes this closes:**
- hard deletes and dangling references;
- code running after its object is deleted;
- timers and processing outliving their owner;
- out-of-sync pairs;
- lost, duplicated or wrongly spilled contents;
- stale state after a prompt or a delay;
- missed wakes, which the audit catches.

**What remains:**
- logic bugs;
- the allowlisted core (MC, world and client procs, admin tools, external I/O);
- the roughly 150 `Destroy()` overrides that hold real domain consequences.

Every old construct has a CI lint with a count ratchet, so no count can grow, and the ratchet is lowered as each sweep lands.

## 2. Where we are (2026-09-26)

| Branch | State |
|---|---|
| `rewrite/om-core`, `rewrite/life-om` | OM core API; Life on OM; tests green |
| `rewrite/om-pipeline` | Pipelines; Life and machines on them |
| `rewrite/om-atmos-machines` | All atmos, hydroponics and the distillery on pipelines and watches; the old gas hibernation deleted; zero atmos `process()`; the focused-test hang fixed |
| `rewrite/om-relations` | Slots are relations; no view fields; occupants, mechs, grabs, pulling, buckling, borers, following, orbiting, leashes, tethers and eyes are all relations |
| `rewrite/om-integration` | Being created: the three branches above merged, then S6 |
| `rewrite/rust-core2` | Core World, stores and events; power, heat and pipes ported; gas mid-cutover |

## 3. Order

Phases run in order; tracks inside a phase run in parallel, one agent per track, split by code folder so that sweeps don't conflict. Each track merges into `rewrite/om-integration` at least daily. Testing is focused tests per slice; the full suite runs only at the gates.

### Phase 0: foundation (running)
| Track | Work | Estimate |
|---|---|---|
| 0a | Integration merge; S6 core: `om_after`, task steps, `om_prompt`, global owner, handles, weak capture; every lint with its baseline count | 5–8 h |
| 0b | Rust: gas cutover, delete the reactor, deduplicate every domain; allowlist to 0 and budgets enforced | 12–20 h |

**Gate 0:** the full suite on the integration branch, then a short benchmark (3 boots per side) against master.

### Phase 1: the bug-heavy sweeps (4 agents)
| Track | Work | Count | Estimate |
|---|---|---|---|
| 1a | S7: `spawn(` to `om_after` and tasks; raw `del(` | 675 + 25 | 8–10 h |
| 1b | S8: `do_after` and gameplay `sleep()` to `om_task` steps | 656 + 554 | 14–18 h |
| 1c | LC-refs part 1: `/datum/weakref` to relations and handles; `GLOB` object lists to registries | 386 + registries | 8–12 h |
| 1d | Remaining pollers (S3–S5): airlocks, cameras, lights, displays, sounds, SSobj/SSprocessing users; machines start asleep | about 60 types | 10–14 h |

### Phase 2: the big mechanical sweeps (4–5 agents)
| Track | Work | Count | Estimate |
|---|---|---|---|
| 2a | S9: `addtimer` to `om_after`, clocks and contributions; delete SStimer | 834 | 10–14 h |
| 2b | Lifecycle sweep: delete the ~200 redundant `Destroy()` overrides, convert the rest to declarations, relations and slots | 1,098 → ~150 | 18–24 h |
| 2c | `qdel` sites to verbs | 4,091 → ~2,000 | 12–16 h |
| 2d | S10: prompts to `om_prompt`; `INVOKE_ASYNC`, `stoplag` and `waitfor` down to the allowlist | ~2,270 + 300 | 18–24 h |

**Gate 2:** full suite, benchmark, and a hard-delete run.

### Phase 3: references and containment (4 agents)
| Track | Work | Estimate |
|---|---|---|
| 3a | LC-refs part 2: every datum-typed instance var and list declared (relation, slot, owned child, handle or cache); the lint to 0. The largest unknown: several thousand vars, and the lint's first run gives the real count | 25–40 h |
| 3b | C3 equipment: body-part slots with layers and aggregates; the per-slot vars, `u_equip` and `get_inventory_slot` deleted | 14–20 h |
| 3c | Organs as keyed internal slots on body parts; C6 machine internals (parts as tiers, boards as types, latent) | 14–20 h |
| 3d | Latent rollout: mapped storage, lights, ammo, pills, then radios and IDs | 10–14 h |

**Gate 3 (final):** merge to master; full suite, hard-delete run and benchmark; then the user's manual playtest.

## 4. Totals

| | Agent hours | Wall clock with the parallelism above |
|---|---|---|
| Phase 0 | 17–28 | about 1 day (Rust is the long pole) |
| Phase 1 | 40–54 | about 1 day |
| Phase 2 | 58–78 | 1–1.5 days |
| Phase 3 | 63–94 | 1.5–2 days |
| Gates and fixes | 10–16 | spread across the gates |
| **Total** | **about 190–270** | **about 5–6 days of continuous running** |

**What could make it longer:**
- DM compile contention when more than about 4 agents compile at once. Concurrent test runs are isolated since the focused-test fix.
- Merge conflicts between sweeps in the same files; splitting by folder and merging daily limits this.
- LC-refs part 2, which is the least well-measured item.
- Behaviour regressions found in manual playtesting; the test suite covers the rest.

**What can be dropped or deferred without breaking the end state:** latent rollout (3d) is a memory win, not a correctness one; C6 machine parts likewise.
