# Completion plan: finishing the rewrite

This plan picks up where [migration_plan.md](migration_plan.md) leaves off. It lists
everything still needed for the rewrite to count as finished: the open migrations, the
consolidations decided on 2026-09-27, the scheduler inversion, the medical lane, and the
gates and cleanup.

Counts were measured on 2026-09-27 from the CI ratchet baselines
(`tools/ci/*_baseline.txt`, `*_allowlist.txt`) and from `git grep` on
`rewrite/om-integration` (om) and `rewrite/reconcile` (recon). Ratchet counts exclude
allowlisted core code, and the targets are written against them.

## 1. The end state

Everything in [migration_plan.md §1](migration_plan.md#1-the-end-state) still applies. These
decisions add to it:

| Concern | The only mechanism | Gone |
|---|---|---|
| Runtime scheduling | the OM scheduler; the MC is a thin kernel (§4) | gameplay subsystems with their own `fire()` loops |
| Reacting now, in the same call (veto, modify in flight) | OM events (`om_emit`, `before/` events with `EVENT_VETO`) | DCS signals (`RegisterSignal`) |
| Reacting later, merged, to state or time | OM channels, watches and `om_after` | signals used for deferred work |
| Per-object add-on behaviour | OM behaviours (shared singletons, state on the entity) | components and elements, `SSdcs` |
| Harm over time, including infections | afflictions; contagion is a trigger plus a transmission profile | `/datum/disease` and its mob procs |
| "These factors for N seconds" | OM timed contributions and statuses (§8.1 of the core doc) | most `/datum/modifier` types |
| Rate limiting | `COOLDOWN_START`/`COOLDOWN_FINISHED`; `om_deadline` when something must happen | raw `world.time > next_x` compares |
| Choosing an action | interactions (Use, Alternate, Menu, category keys) | intents, `IS_HARMING`-style stance reads, radial and `tgui_alert` action pickers |
| Death consequences | declared destroy hooks on behaviours | `Destroy()` overrides (a lint forbids them once the hooks exist) |

**What remains by design:**
- about 15–20 core subsystems (§3.6);
- about 150 declared destroy hooks with real domain consequences;
- a small allowlist of tg-inherited core code (tgui, MC, client, TGS);
- logic bugs.

## 2. Where we are (2026-09-27)

### 2.1 Branches
| Branch | State | Next |
|---|---|---|
| `rewrite/om-integration` | integration head; wave 2 and `narrow-procs` merged; 4 compile errors carried from earlier | merge into master through `integrate/all` |
| `rewrite/reconcile` | w5, w6 design/audit, the Codex snapshot and ~10 small branches, adapted to OM at an older fork point | being merged into `integrate/all` (108 conflicting files) |
| `w6/integrate` | clock core, revive/death, part slots; leftover fixes committed | merged into `integrate/all` after reconcile |
| `integrate/all` (`E:/projects/dq-merge-all`) | om-integration + reconcile merge in progress | compile, lint, gripper test, full suite, then master and push |
| `rewrite/p2-timers` | `addtimer` 0, SStimer deleted; 9 commits, clean | merge after `integrate/all` |
| `rewrite/p2-prompts` | prompts 2,234 → 61; 16 files uncommitted | commit, finish, merge |
| `rewrite/p3-refs` | LC-refs 2,684 → 2,114 committed; 154 files uncommitted | commit, continue (§3.3) |
| `life-bench-base`, `life-bench-master` | benchmark branches | tag, then delete |

### 2.2 Migration counts
| Target | Start | Now | Goal |
|---|---|---|---|
| machinery `process()` | 192 | 0 | 0 ✅ |
| `START_MACHINE_PROCESSING` | 149 | 1 | 0 |
| `START_PROCESSING` | 224 | 2 | 0 |
| pollers / deadline polling ratchets | — | 0 / 0 | 0 ✅ |
| `do_after` | 656 | 0 | 0 ✅ |
| `/datum/weakref` | 386 | 0 | 0 ✅ |
| `spawn(` | 675 | 32 | allowlist |
| raw `del(` | 25 | 13 | 0 |
| gameplay `sleep()` | 554 | 24 | allowlist |
| `addtimer` | 834 | 786 (0 on `p2-timers`) | 0 |
| prompts | 2,270 | 2,234 (61 on `p2-prompts`) | allowlist |
| `INVOKE_ASYNC` | 126 | 113 | allowlist |
| `stoplag` | 68 | 51 | allowlist |
| `set waitfor` | 109 | 70 | allowlist |
| unjustified `Destroy()` | 1,098 | 0 (366 with `// LIFECYCLE:` reasons) | 0 ✅, then ~150 hooks |
| `qdel(` sites | 4,091 | 2,122 | ~2,000 |
| LC-refs: undeclared vars | ~2,700 | 2,684 (2,114 on `p3-refs`) | 0 |
| LC-refs: object-keyed lists | ~600 | 602 (314 on `p3-refs`) | 0 |
| raw `loc`/`contents` writes | — | 601 (590 recon) | 0 |
| latent raw contents walks | — | 126 (93 recon) | 0 |
| registries allowlist | — | 2 | 0 |
| `timer_cooldown` | — | 3 | 0 |
| `attackby` overrides | 874 | 654 (553 recon) | 0 |
| `attack_hand` overrides | 635 | 377 (303 recon) | 0 |
| `a_intent` | 211 | 29 (13 recon) | allowlist |
| stance reads (`IS_*`, `use_stance`) | — | 370 (recon) | 0 |
| `description_info` | 397 | 378 | 0 |
| `RegisterSignal` | — | 453 | allowlist |
| `AddComponent` / `AddElement` | — | 175 / 170 | 0 |
| `/datum/disease` types | — | 104 | 0 |
| `/datum/modifier` types | — | 421 | medically real ones only |
| raw `world.time` cooldown compares | — | 158 | 0 |
| subsystems | — | 87 | ~15–20 core |
| `SSmachines` refs | 321 | 138 | 0 |

## 3. Workstreams

Each workstream lands in slices, merges into `rewrite/om-integration` as soon as it is
green, and lowers its ratchet in the same commit. Estimates are agent hours.

### 3.0 Land what is done (first, blocking)
| Step | Work | Estimate |
|---|---|---|
| 0.1 | Finish `integrate/all`: resolve the reconcile conflicts, merge `w6/integrate`, fix the 4 inherited compile errors, lint | 3–6 h |
| 0.2 | Re-run `dq_refs_gripper_holding`; full suite; fix merge-caused failures (prove others pre-existing with `test-baseline`) | 2–4 h |
| 0.3 | Merge into master and push (**needs the user's approval**: the auto-mode classifier blocks it) | — |
| 0.4 | Merge `p2-timers` (SStimer deleted). Commit and finish `p2-prompts` (61 left), merge | 3–5 h |
| 0.5 | Commit `p3-refs`'s 154 files; merge what is green | 1–2 h |
| 0.6 | Cleanup: tag and delete the life-bench branches; remove the `dq-wt/*` lanes that are merged, `dq-wt/recon`, `CHOMPStation2-body-baseline`, `review-fixes`, `dq-merge-all`, `dq-w5-*`/`dq-w6-*`. Keep `dmb-format` (Codex). Decide on `verdigris/target-lead` and `target-events` (~3.4 GB) | 1 h |

**Gate A:** master holds all finished work; full suite green; benchmark against the F1 baseline.

### 3.1 Finish the scheduling sweeps
| Item | Work | Count | Estimate |
|---|---|---|---|
| S7 | the last `spawn(` and raw `del(` | 32 + 13 | 2–3 h |
| S8 | the last gameplay `sleep()` | 24 | 2 h |
| S10b | `INVOKE_ASYNC`, `stoplag`, `set waitfor` down to the allowlist (the callees no longer sleep once S8–S10 land) | 113 + 51 + 70 | 6–10 h |
| S-cool | cooldowns: raw `world.time` compares to `COOLDOWN_*` or `om_deadline`; add the ratchet lint; `timer_cooldown` to 0 | 158 + 3 | 4–6 h |
| S-proc | the last `START_PROCESSING` / `START_MACHINE_PROCESSING` | 3 | 1 h |

### 3.2 Events: signals and components onto OM (decision 2)
Rule: **OM events for "now", OM watches/`om_after` for "later"**. DCS signals and
components go away except for an allowlist of tg-inherited core code.

| Step | Work | Estimate |
|---|---|---|
| E0 | Ratchet lints for `RegisterSignal`, `AddComponent`, `AddElement` at today's counts; document the rule in the core doc §16 | 1 h |
| E1 | Map every signal in use to its replacement: synchronous with veto → `before/` event; synchronous notify → event; deferred or state-driven → channel or watch | 3–4 h |
| E2 | Migrate domain by domain, **in the same pass as LC-refs for that domain** (§3.3), since each registration is a reference edge | with §3.3 |
| E3 | Components → behaviours (state on the entity); elements → shared behaviour singletons | 12–18 h |
| E4 | Delete `SSdcs` and the DCS core outside the allowlist | 2 h |

### 3.3 LC-refs: declared references (the largest item)
Every object-typed var or list is a slot, `REF_OWNED(_LIST)`, `REF_PAIR`, `REF_BACKLIST`,
an OM handle, or a declared cache with a `CACHE_ON_*` rule
([lifecycle.md §4](lifecycle.md#4-declared-references)).

| Step | Work | Count | Estimate |
|---|---|---|---|
| R1 | Continue `p3-refs` by folder (`__defines`, `_helpers`, `controllers`, `_onclick` are at 0), with the signal migration (E2) for each folder | 2,114 vars | 25–35 h |
| R2 | Object-keyed lists | 314 | 6–10 h |
| R3 | The hard files one at a time: mecha (22), robot (20), AST statements (17), rig (14), pAI (13), sunlight (13), flight types (12), newscaster (12) | ~120 | 6–8 h |
| R4 | Last 2 registries off the allowlist | 2 | 1 h |

### 3.4 Containment and slots
| Item | Work | Count | Estimate |
|---|---|---|---|
| C11 | raw `loc =`/`contents` writes through the ledger API | 590 | 10–14 h |
| C-lat | latent raw contents walks | 93 | 3–4 h |
| C3 | equipment on body-part slots; delete per-slot vars, `get_inventory_slot` (15) | — | 14–20 h |
| O-slots | organs as keyed internal slots (`internal_organs_by_name`: 300) | 300 | 10–14 h |
| C6 | machine internals as data: parts as tiers, boards as types (`component_parts`: 89). Optional | 89 | 8–12 h |
| C5 | latent rollout: mapped storage, lights, ammo, pills, then radios and IDs. Optional (memory win) | — | 10–14 h |
| C8b | mech damage through the body model (`injure()`) | — | 8–12 h |

### 3.5 Destruction
| Step | Work | Estimate |
|---|---|---|
| D-hooks | a declared destroy hook on behaviours (`on_destroy` phase), run by the destroy transaction | 3–4 h |
| D-move | move the remaining `// LIFECYCLE:` overrides into hooks. LC-refs (§3.3) and E2 should remove ~200 of the 366 first (pair and backlist cleanup, `UnregisterSignal`) | 8–12 h |
| D-lint | forbid `Destroy()` overrides outside the allowlist (the MC, datums with no entity) | 1 h |
| D-qdel | the last `qdel(` sites to verbs | 2,122 → ~2,000 | 2–3 h |

### 3.6 Scheduler inversion: subsystems onto OM
The MC becomes a thin kernel: tick budget, failsafe and `Recover`, boot and runlevels,
profiling. The OM scheduler (`SSbehaviours`) is the only runtime scheduler for gameplay.

**Core subsystems that stay** (~15–20): `ticker`, `garbage`, `atoms`, `mapping`, `air`
(drives the Rust world step), `vg`, `behaviours` (the OM scheduler), `dbcore`, `sqlite`,
`tgui`, `chat`, `input`, `statpanels`, `verb_manager`, `speech_controller`, `server_maint`,
`ping`, `assets`, `early_assets`, `asset_loading`, `overlays`, `vis_overlays`, `runechat`,
`profiler`, `time_track`.

**Feature services** (kept as named services; re-expressed as OM services with no fire
loop where they poll): `expedition`, `flight_operations`, `job`, `research`, `shuttles`,
`emergency_shuttle`, `persistence`/`persist`, `transcore`, `vote`, `contracts`, `supply`,
`character_setup`, `access`, `admin_verbs`, `internal_wiki`, `holomaps`, `robot_sprites`,
`media_tracks`, `player_tips`, `lobby_monitor`, `nerdle`.

**Folded into OM** (periodic lanes, behaviours on entities, registries):

| Wave | Subsystems | Notes |
|---|---|---|
| F1 | `timer` (done on `p2-timers`), `machines`, `mobs`, `plants` | already mostly shells over pipelines |
| F2 | `ai`, `aifast`, `dq_combat_ai` → one AI brain on OM pipelines; `pathfinder` as a service | three subsystems for one job |
| F3 | `chemistry`, `radiation`, `instruments`, `throwing`, `sounds`, `motiontracker`, `reflector`, `pai`, `circuit`, `xenoarch`, `looting`, `mail`, `events` | classic polling loops today; gain clocks, stasis and relevance |
| F4 | `sun`, `solars`, `nightshift`, `planets`, `skybox`, `starmover`, `turf_cascade`, `explosions`, `radio`, `points_of_interest`, `inactivity`, `antag_job`, `transfer`, `properties` | world-level periodics on the global owner entity |
| F5 | `lighting` (after Phase 4f makes it a Rust field), `dcs` (after E4) | depend on other workstreams |

| Step | Work | Estimate |
|---|---|---|
| K1 | Boot on declared dependencies: services declare `order_after`; `init_order` numbers go | 4–6 h |
| K2 | OM admin profiling panel with per-behaviour and per-lane cost, before subsystems leave the stat panel | 3–4 h |
| K3 | Fold waves F1–F5 | 30–45 h |
| K4 | Lint: subsystems with a `fire()` only on the core allowlist | 1 h |
| K5 | Isolation check: a failing behaviour or lane must not stall the scheduler (per-behaviour error isolation already exists; add a test per lane) | 2 h |

### 3.7 Interactions and input (track I)
| Item | Work | Count | Estimate |
|---|---|---|---|
| I7 | convert `attackby`, `attack_hand`, `attack_self`, `click_alt`, `MouseDrop_T` and object verbs, domain by domain (machinery → structures → items → mobs → turfs); delete legacy procs per domain; then remove the `attackby` fallback | 553 + 303 + ~500 + 88 | 30–45 h |
| I6b | replace stance reads with real hostile/non-hostile interactions (with I7) | 370 | with I7 |
| I-menu | radial and `tgui_alert` action pickers → the Menu action or `om_prompt` | 68 radials | 4–6 h |
| I3 | actor adapters; delete forwarding `attack_ai`/`attack_robot`/`attack_ghost`/`attack_tk` | 64 + 89 | 6–8 h |
| I1 | input layer: actions, bindings, keybind preferences, one router; replace the `skin.dmf` macro sets and the three modifier ladders | — | 14–20 h |
| I2b | generated examine text and screentips; delete `description_info` per domain | 378 | with I7 |

### 3.8 Remaining roadmap tracks
| Item | Work | Estimate |
|---|---|---|
| P1–P3 | property registry, predicates, constraints replacing `can_hold`, `species_restricted`, `slot_flags` checks (verify how much is already gone first) | 12–20 h |
| H1 | DM thermal API and generated constants (verify against M4) | 2–4 h |
| H2 | nothing writes `bodytemperature` directly (93 writes); clothing through slots (after C3) | 6–10 h |
| H3 | `fire_act` variants (51) and burning through rules | 6–8 h |
| H4 | thermal regulator for machines | 6–10 h |
| D2 | interned armour, deterministic mitigation (after C3) | 8–12 h |
| D4 | declarative break thresholds; delete `atom_break`/`set_broken` copies | 6–8 h |
| D5v | verify D5: 133 `ex_act(` remain despite the merged branch | 1–2 h, then as found |
| D-turf | turf damage onto the damage packet and integrity | 4–6 h |
| M3b | delete the DM powernet (`/datum/powernet`, 65 refs) | 6–10 h |
| M5 | radiation through rays and an insulation layer | 8–12 h |
| M6 | generation planners into `vg-layout` | 10–16 h |
| L1, L2, L4 | state schema and serializer; `on_materialize` split; signal audit (L4 largely replaced by §3.2) | 12–20 h |
| G-traits | the last 54 `ADD_TRAIT` onto grants | 2–3 h |

### 3.9 Medical and body lane
| Item | Work | Estimate |
|---|---|---|
| MED-0 | the owed object-model review (`doc/rewrite/object_model.md`); lifts DQ Cleanup's hold on life systems, grants, traits/genes, body destruction and species | 2–3 h |
| MED-1 | re-triage `doc/medical_audit_findings.md` (147 rows, 4 days old; w6/critical fixed some) | 1–2 h |
| MED-2 | P0 fixes: cyborg thermal runaway soft-lock, vodka radiation doubling, double `death()` side effects, mind identity overwriting the body's, tourniquet/surgery/limb runtimes | 4–6 h |
| MED-3 | P1 fixes (~40 wrong medical results) | 10–14 h |
| MED-4 | **diseases → afflictions** (decision 1): stages, cures, visibility and viable mob types map onto affliction stages, `treatment_tags`, symptoms and `biology`; spread becomes a contagion trigger with a transmission profile on a parkable periodic lane; `strain_data` becomes variant data. Delete `/datum/disease` (104 types) and `_MobProcs.dm` | 12–18 h |
| MED-5 | **modifiers → contributions**: short factor-only modifiers become OM timed contributions; medically real ones become afflictions. 421 types | 14–20 h |
| MED-6 | w5 life rules stop polling (wake on events) | 4–6 h |
| MED-7 | frameworks from the tracker: clock, ownership, exposure, heat, vitals (~50 findings) | 20–30 h |
| MED-8 | P2 performance and P3 cleanup rows | 8–12 h |

### 3.10 Phase 4: boot and memory
Southern Cross boots in about 121 s (target 35–45 s). Rust boot memory peaks at 1.85 GB (target about 1 GB).

| Track | Work | Status | Estimate |
|---|---|---|---|
| 4a | quick fixes (pipenet join, asset/holomap/wiki caches, contract damage per explosion epoch) | `boot-perf` merged; verify coverage | 1–2 h |
| 4b | Rust boot memory peak down | not started | 4–8 h |
| 4c | type tables and lazy `Initialize()`; the `Initialize` ratchet | started | 12–18 h |
| 4d | chunked materialize | not started | 10–14 h |
| 4e | batched destroy per-set domain hooks and per-turf effects | partial | 4–8 h |
| 4f | lighting as a Rust core field | not started | 16–24 h |

Fill in the roadmap's benchmark-target table first (Metric / Baseline / Target), and gate
each Phase 4 track on it.

### 3.11 Developer experience and "nothing waits" (approved 2026-09-27)
Two principles: **nothing in gameplay waits** (all waiting lives in a few named executors
and lanes owned by the OM core), and **declare once, generate the rest**.

| Item | Work | Status |
|---|---|---|
| DX-io | OM I/O jobs: `om_io(E, /datum/om/io/sql or http, ..., on_done)` on an I/O lane that polls rust-g async jobs; owned by E, args as handles. Migrate SQL waits and `world.Export`; delete the related `set waitfor`/`INVOKE_ASYNC`/`stoplag`/`spawn` allowlist entries | `rewrite/d-io` running |
| DX-exec | one executor for BYOND's remaining blocking built-ins (`winget`, `MeasureText`, `shell()`) so their allowlist is one file | after DX-io |
| DX-field | `OM_FIELD(type, name, default, channel)` generates the var, `set_<name>()` and the registration; stage `wake_on` derived from `reads`; migrate the ~26 fields; field-write lint covers all code and tests | `rewrite/d-fields` running |
| DX-field-dmh | `tools/dm-health` (Codex's AST checker, which already has `tracked(setter=...)`, `private`, `protected`, `readonly`) treats `OM_FIELD` fields as tracked; it becomes the enforcement layer and the Python field lint the stopgap | request sent to Codex |
| DX-allow | one inline annotation, `// ALLOW(<lint>): <reason>`, read by every lint; the per-lint `*_allowlist.txt` count files go (ratchet baselines stay) | after batch 1 lands |
| DX-interact | `DECLARE_INTERACTIONS(type, ...)` generates the `get_interactions()` static-list getter; convert existing specs; I7 continues in the final form | after batch 1 lands, before I7 resumes |
| DX-docs | a one-page "which time mechanism" table (`om_after`, `om_deadline`, `COOLDOWN_*`, clocks, rewakes, lanes) and an "OM in 10 minutes" onboarding doc | any time |
| DX-dmh | converge the Python lints in `tools/ci` into `dm-health ci-suite` over time (coordinate with Codex, who owns `tools/dm-health`) | later |
| DX-prompt | typed prompts (`/datum/om/prompt/<kind>` subtypes with typed vars, `ask.yes`/`ask.choice`, `requires` covering the common re-checks), launched with `om_ask()`; ratchet on the list form | `rewrite/e-prompts` running |
| DX-task | named task parameters: `om_task_start(type, actor, target, name = value, ...)` into the task's typed vars; receiver defaults to the target | `rewrite/e-prompts` running |
| DX-flow | a declared multi-step flow type (task → prompt → effect sharing typed state), so one action is one type instead of several procs | `rewrite/e-prompts` running |
| DX-refs | `REF_DEF` (frozen definitions), `REF_TRANSIENT` (pooled scratch fields, cleared on release), generic `POOL_DECLARE`/`pool_take`/`release` with poisoning in tests, one-place `REF_VAR`; base-type proc ceiling removed | `rewrite/d-refkinds` running |
| Lint gaps | registry lint catches any global list that holds objects, not only self-registration (the `latency_sweep` bug class) | with LC-refs |

## 4. Order and parallelism

Tracks inside a phase run in parallel, one agent per track, split by code folder.
Each merges into integration at least daily.

| Phase | Tracks | Wall clock |
|---|---|---|
| A | §3.0 land what is done; MED-0 review; MED-1 re-triage | ~1 day |
| B | §3.1 sweeps · E0–E1 · K1–K2 · MED-2 · F1 fold · 4a/4b | ~1 day |
| C | §3.3 LC-refs + E2 (by folder, 2–3 agents) · MED-4 diseases · F2 AI fold · C11 | 2–3 days |
| D | E3 components · D-hooks/D-move · C3 + O-slots · MED-5 modifiers · I7 machinery+structures · F3 fold | 2–3 days |
| E | I7 items/mobs/turfs + I6b + I2b · I3 · I1 · H2/H3/H4 · D2/D4/D-turf · M3b · F4 fold · 4c/4d | 3–4 days |
| F | E4, D-lint, K4, F5 fold · 4e/4f · M5/M6 · L1/L2 · MED-6–8 · optional C5/C6 | 2–3 days |

**Dependencies that decide the order:**
- LC-refs and the signal migration touch the same files: one pass per folder.
- D-move waits for LC-refs and E2 (they remove ~200 overrides).
- C3 before H2 (clothing) and D2 (armour).
- Phase 4f before folding `lighting`; E4 before folding `dcs`.
- MED-0 before any code touching life systems, grants, body destruction or species.

## 5. Gates

| Gate | When | What |
|---|---|---|
| A | after §3.0 | full suite, benchmark vs the F1 baseline |
| B | end of phase C | full suite, hard-delete run, benchmark |
| C | end of phase E | full suite, hard-delete run, benchmark, missed-wake audit clean |
| Final | end of phase F | full suite, hard-delete run, benchmark against the Phase 4 targets, every ratchet at its goal (§2.2), then the user's manual playtest |

Full-suite runs happen only at gates or when the user asks. Slices run focused tests.

## 6. Totals

| Area | Agent hours |
|---|---|
| §3.0 landing | 10–18 |
| §3.1 sweeps | 15–22 |
| §3.2 events and components | 18–25 |
| §3.3 LC-refs | 38–54 |
| §3.4 containment (C5/C6 optional: +18–26) | 45–64 |
| §3.5 destruction | 14–20 |
| §3.6 scheduler inversion | 40–58 |
| §3.7 interactions and input | 54–79 |
| §3.8 other tracks | 110–170 |
| §3.9 medical | 75–110 |
| §3.10 Phase 4 | 47–74 |
| **Total** | **about 470–690** (plus 18–26 optional) |

At 4–5 parallel agents this is roughly 11–16 days of continuous running.

**What could make it longer:** DM compile contention above ~4 agents; merge conflicts
between sweeps (split by folder, merge daily); LC-refs judgement calls on big stateful
types; behaviour regressions found in playtesting; the auto-mode permission classifier
blocking merges to master and pushes (the user approves those).

**What can be deferred without breaking the end state:** C5 latent rollout, C6 machine
parts, M6 planners, 4f lighting (then `lighting` stays a core subsystem).

## 7. Decisions (approved by the user, 2026-09-27)
1. **Approved:** the events rule (§3.2). Signals and components go away outside a core allowlist.
2. **Approved:** diseases → afflictions (MED-4) and modifiers → contributions (MED-5) on the medical lane.
3. **Approved:** the scheduler inversion (§3.6) and its core subsystem list.
4. **Approved and done:** `verdigris/target-lead` and `target-events` deleted.
5. **Approved:** merges into master are allowed without asking each time, once a branch is green (compile, lint, and its tests; the full suite at gates).
6. **Deferred (2026-09-27):** C5 latent rollout, C6 machine parts, M6 generation planners, 4f lighting as a Rust field. `lighting` stays a core subsystem until 4f is picked up.
