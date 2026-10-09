# DeepQuarry systems design: one scheduler, self-contained systems

**Status:** design proposal. It is read-only work: no repo files were changed.

**Inputs:**
- `systems_audit.md` (same scratchpad) is the "before" evidence. Every number quoted here is
  defined there.
- `final_design.md` (the approved DX design) sets the style. The rules this design follows from it:
  - ordinary DM;
  - configuration as type vars;
  - behaviour as overrides of well-known procs;
  - tables as procs that return lists;
  - capabilities as the unit of features;
  - `changed()`, `should_run()` and `periodic_step(dt)`;
  - the fewest possible macros.
- The DX framework code lives in `E:/projects/dq-dx-framework` (`rewrite/dx-framework`, which is
  `integrate/b17` merged with the DX core), in `code/datums/capabilities/`.
  - This design grows directly out of the stub already there: `/datum/cap_system` with `members`,
    `join()`/`leave()`, and `capability.joins` / `systems()`.
  - Source: `code/datums/capabilities/capability_ext.dm:126-158`.

All code quoted as **current** comes from the dx-framework worktree, with file:line references.
Where the numbers differ from b17 by a few lines, the dx tree wins.

---

## 0. What changes, in one page

**Today.** One gameplay tick passes through all of these:

- the MC (`master.dm` `Loop`/`CheckQueue`/`RunQueue`, 1,207 lines), which serves 11 firing
  subsystems;
- one of those subsystems, SSbehaviours, which runs the OM scheduler;
- inside the scheduler, 5 lanes, a deadline wheel, cadence rings, 22 pipelines and 34
  world-service lanes;
- the Rust world, stepped from 4 places.

**Ways to repeat something.** Counting the declaration forms found while writing this design,
there are **13**:

| # | Form | Uses |
|---|---|---|
| 1 | `fire()` | - |
| 2 | behaviour `every` | - |
| 3 | stage `rewake_delay` | - |
| 4 | `om_task_periodic` | - |
| 5 | `DECLARE_PERIODIC_WHILE` | 158 |
| 6 | `DECLARE_REPEAT` | 58 |
| 7 | world lanes | - |
| 8 | `om_after_replace` loops, stagger and drift | - |
| 9 | world watches | - |
| 10 | Rust law periods | - |
| 11 | `vg_heat_tick` | - |
| 12 | slices | - |
| 13 | `/world/Tick` callbacks | - |

Every world-level unit (29 subsystems and 44 services) talks to the others through direct calls and
field pokes:

- 63 system→system edges
- 4 cycles
- 1,657 external field accesses, 242 of them writes

**Target:**

1. **One kernel scheduler.** It is the OM scheduler, promoted. The MC becomes a thin host that
   keeps only the tick budget, the failsafe, runlevels and a 5-item kernel allowlist (garbage,
   input, verb_manager, dbcore, tgui transport).
2. **Three time primitives and one sleep rule.** Everything that runs does so because of one of:
   - a **cadence**: `periodic_cadence` + `should_run()` + `periodic_step(dt)`
   - a **deadline**: `om_after()` / `om_after_slot()` / `timed_set()`
   - a **change**: `changed()` → re-evaluate → wake

   Anything whose `should_run()` is FALSE is parked and costs nothing. Mob hibernation, machine
   parking, on-demand services and periodic-lane stop/start are all this one rule.
3. **One unit: `/datum/system`.** It replaces `/datum/controller/subsystem` (except the kernel
   five), `/datum/world_service` (44) and `/datum/cap_system`. A system:
   - declares its `needs` (the boot DAG), its cadence, its members (through capabilities), its
     `api()`, and the events it `emits` and `handles`
   - owns its state, which is `VAR_PRIVATE` and enforced by DreamChecker
   - is reachable from outside only through the procs in its folder's `api.dm`, enforced by
     `tools/ci/system_boundary_lint.py`
4. **Capabilities bring systems.** `/datum/capability/proc/systems()` already exists in the DX
   stub. An atom joins every system its capabilities name when it initializes and leaves when it
   is destroyed. Systems iterate `members`; they never scan the world.

---

## 1. One scheduling model

### 1.1 What exists (condensed from the audit)

| Layer | Mechanism | Where | Scale |
|---|---|---|---|
| Host | MC `Loop` → `CheckQueue` → `RunQueue` → `ignite` → `fire` | `code/controllers/master.dm:606-1110`, `subsystem.dm:160-186` | 11 firing subsystems, per-SS `wait`/`priority`/`flags`/`runlevels` |
| Scheduler | `SSbehaviours.fire()` → `sched.run_pass()` | `controllers/subsystems/behaviours.dm:29-34`, `datums/om/scheduler.dm:305-359` | 1 of the 11 |
| Cadence | behaviour `every`, relevance intervals, fixed steps | `datums/om/defs.dm:24-72` | 70 `every =` |
| Pipelines | ordered stages, `idle()`, `rewake_delay()`, `min_interval`, park/unpark | `datums/om/pipeline.dm` (1,027 lines) | 22 pipelines, 294 stages |
| Periodic lanes | `om_task_periodic(E, PERIODIC_X)` → `periodic_step(delta)` | `datums/om/periodic.dm` | 11 pipelines, 341 `periodic_step` |
| Declared periodic | `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT` | `datums/sys/periodic.dm`, `__defines/sys_periodic.dm:43` | 158 + 58 |
| Machine step | `machine_step()`, `MACHINE_WAKE/SLEEP`, `step_active` | `game/machinery/machine_pipeline.dm:300-315` | 227 / 130 |
| World lanes | `/datum/om/behaviour/world/X` → `service_step(resumed)` | `datums/om/world_lanes.dm:155-190` | 34 |
| Timers | `om_after*`, `om_after_slot`, `om_deadline` (DM deadline wheel) | `engine/time/timers.dm` (was `datums/om/timer.dm`), `deadline.dm` | about 1,560 + 59 + 31 |
| Rust wheel | `om_world_at/on_key/on_change/when/on_rate` → `vg_world_step` | `datums/om/world_watch.dm:196-230` | 35 |
| Rust pacers | `vg_world_tick` (SSvg), `vg_heat_tick` (SSair), event drains in 2 places | `vg.dm:75-77`, `SSair.dm:215`, `heat.dm:365-369` | 4 drivers |
| DX refresh | `changed()` → `refresh_queue` → `refresh_one()` (draw, verbs, UIs, `should_run`) plus a sweep | `datums/capabilities/refresh.dm:24-205` | presentation lane |
| Misc | `/world/Tick` callbacks, `om_task_slices`, `speed_process` fast lane | `game/world.dm:692`, `datums/om/timed_action.dm:364` | - |

**What the OM scheduler already gets right, and the kernel therefore keeps:**
- one budgeted pass per tick;
- lanes with guaranteed shares;
- a deadline wheel with no datum per timer;
- phase-spread cadence rings;
- parking;
- per-behaviour error isolation (`run_lane_guarded`, `scheduler.dm:372`);
- a deterministic test harness (`om_test_begin` / `scheduler_advance`).

**What is wrong is everything around it:**
- a second scheduler on top (the MC) with its own priority model;
- the world-level units that bypass the lanes (air, vg, lighting, ticker, tgui, profiler);
- five ways of saying "run while X", each with its own start/stop vocabulary: `om_task_periodic`,
  `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT`, `MACHINE_WAKE`, world-lane `on_demand`;
- no single owner of the Rust clock.

### 1.2 The kernel

The kernel is the OM scheduler plus the host loop that the MC does today. It lives in
`code/controllers/kernel/`:

| File | Contents | Replaces |
|---|---|---|
| `kernel.dm` | the host loop | MC `Loop`/`RunQueue` for gameplay |
| `boot.dm` | the boot DAG | MC `Initialize` stage loop, `boot_world_services_after` |
| `kernel_subsystems.dm` | the 5 kernel subsystems, unchanged tg code | - |
| `failsafe.dm` | moved as is | - |

`code/datums/om/scheduler.dm` stays the engine.

**One pass per tick, in fixed phases:**

```
kernel_tick():
  budget = TICK_LIMIT_RUNNING - TICK_USAGE
  phase K  kernel subsystems (input, verb_manager): run first, unbudgeted but capped (latency)
  phase N  native: ONE Rust driver (vg_world_tick + vg_heat_tick + vg_world_step + one event drain)
  phase D  deadlines (timers, deadline wakes, timed_set reverts)          >= 20% of budget
  phase B  borrow: rings near max_interval                                 from the whole budget
  phase L  lanes URGENT 30 / SIMULATION 30 / DERIVED 15 / PRESENTATION 15 / BACKGROUND 10
           each lane: queued wakes -> system steps -> member rings -> (PRESENTATION) refresh drain
  phase R  leftovers, lane order; then phase-L work items that ran out of their lane share with work left (p_carry)
  phase G  garbage (kernel subsystem), whatever is left, with a floor per second
```

Phases D, B, L and R are today's `run_pass()` unchanged. The new parts are K, N and G. K and G
are the MC's remaining duties; N consolidates the Rust drivers.

**The unit of work** is always one of three things. There is no fourth kind.

| Work item | Queued by | Runs | Accounting key |
|---|---|---|---|
| **cadence slot** (entity E, cadence C) | `should_run()` became TRUE | `E.periodic_step(dt)`, or `S.member_step(E, dt)` for a system's members | the system that owns C |
| **deadline** (E, slot) | `om_after`, `om_after_slot`, `timed_set`, a stage rewake | the stored proc, if E and every datum argument is alive | the owning system of E's type, or `global` |
| **wake** (E, bits) | `changed(E, channel)` | the refresh of E: re-evaluate `should_run()` for every cadence and system E is in, then draw, verbs and UIs | presentation lane (refresh) plus the woken system |

**Priorities are lanes, and a system picks its lane** (a type var). The MC's `priority` numbers
(`FIRE_PRIORITY_*`) and `SS_TICKER`/`SS_BACKGROUND` go away:

| MC concept | Kernel equivalent |
|---|---|
| priority | lane share |
| `SS_TICKER` | `periodic_cadence = CADENCE_TICK` |
| `SS_BACKGROUND` | `lane = LANE_BACKGROUND` |
| `SS_KEEP_TIMING` | `max_interval` borrow |
| `SS_POST_FIRE_TIMING` | what a cadence does by default (it is re-armed from the end of the step) |
| `runlevels` | the same type var on the system, read by the ring |

### 1.3 Cadences, `should_run()` and sleep: one rule for everything

The DX API is already on every datum (`refresh.dm:26, 95-105`):

```dm
/// The periodic pipeline should_run() gates, or null for no periodic work. A type var.
/datum/var/periodic_cadence = null
/datum/proc/should_run()           // re-evaluated on change
/datum/proc/periodic_step(dt)
```

The kernel makes these the only way to repeat:

- **A cadence** is a `/datum/cadence` singleton, and `periodic_cadence` names one.
  - It declares `interval`, `lane`, `max_interval`, `clock` (world, bio, machine) and `runlevels`.
  - Today's periodic pipelines become the standard cadences:

| Cadence | Interval | Replaces |
|---|---|---|
| `CADENCE_TICK` | 1 tick | the `continuous/*` pipelines and SS_TICKER |
| `CADENCE_FAST` | 0.2 s | - |
| `CADENCE_SECOND` | 1 s | - |
| `CADENCE_SLOW` | 2 s | also `MACHINE_PIPELINE` |
| `CADENCE_LIFE` | `LIFE_CYCLE`, fixed step | - |
| `CADENCE_MINUTE` | 1 min | - |

  - A type that needs its own interval sets `periodic_interval` (a type var or a proc). This covers
    `DECLARE_REPEAT`'s `"magnet_delay"`.
- **Sleep is `should_run()` returning FALSE.** On every `changed(E)`, the refresh re-evaluates
  `should_run()` and puts E on or off the ring, as `refresh_periodic()` already does at
  `refresh.dm:161-170`. Two more ways to leave the ring:
  - `periodic_step()` returning `PROCESS_KILL` parks E until the next change.
  - A step can `return rewake_in(4 SECONDS)` to park and wake on a deadline instead. This
    replaces stage `rewake_delay()`.
- **Hibernation, generalised.** A mob, machine, service or item is asleep when every cadence it has
  is parked. The two audits merge into one:
  - The OM missed-wake audit (`om_pipeline_audit`) and the refresh sweep's `should_run()` drift
    check (`refresh.dm:262-280`) are the same check. The sweep is kept.
  - In test builds a drift is a failure (`REFRESH DRIFT`), exactly as today.
- **Relevance and clocks** stay cadence properties, so there is no new mechanism. Examples:
  - Life's `relevance = list(OM_PARK, …)` parks mobs on empty z-levels.
  - `clock = CLOCK_BIO` pauses in stasis.

**Stages** (Life has 232 and machines 52) remain the way a system orders work inside one member's
step. Each stage adopts the same vocabulary: `should_run(self)` instead of `idle()` (inverted),
`periodic_step(self, ctx)` instead of `perform()`, and `rewake_in()` instead of `rewake_delay()`.

Stages keep a `wake_on` channel mask **as an optional filter**. It is a type var, not a macro. It
exists because a walking mob raises `CHANGE_MOB_LOC` most ticks, and re-evaluating 66 families'
`should_run()` on every change would cost more than the mask test. The `life_sweep` bench decides
whether each mask earns its place.

### 1.4 Timers, deferred work and slices: one mechanism

| Today | Kernel form | Notes |
|---|---|---|
| `om_after(E, d, PROC_REF(x), …)` | unchanged | owned by E, weak arguments, on E's clock (`timer.dm:257-281`) |
| `om_after_slot(E, "name", d, …)` | unchanged | named slot, one per (E, name) |
| `om_after_unique` / `om_after_replace` | `om_after_slot` | a slot is unique by construction; replacing is re-arming the slot |
| `om_after_replace` self-loops, `om_after_stagger`, `om_after_drift` | a cadence | lint `kernel_timer_loop`: a proc that re-arms its own slot is periodic work |
| `DECLARE_REPEAT(T, delay, proc, field)` | `periodic_cadence` + `periodic_interval` + `should_run()` | 58 sites |
| `timed_set(src, nameof(v), x, for_time =)` | unchanged (DX §7) | a deadline slot that writes back through the setter |
| `om_deadline(E, d, B, sub)` | internal only | the kernel's primitive under stage rewakes and slots; not public |
| `world_next_tick(spec)` (`/world/Tick`) | kept for world procs only | it has to run after the MC shuts down, so it cannot be a deadline |
| `om_task_slices`, a yielding `service_step` | a system `periodic_step()` returning `STEP_YIELD` | the kernel resumes it on the next tick, as world lanes do today (`world_lanes.dm:170-186`) |
| `INVOKE_ASYNC` / `set waitfor` in handlers | the dispatcher (DX) | already banned outside the allowlist |
| `om_world_at` (Rust wheel) | deleted in E6 | a DM time is the kernel's `after()`; the Rust wheel keeps only rate crossings |

That leaves exactly two wheels:
- the DM deadline wheel, for DM work on entity clocks;
- the Rust timing wheel, for Rust-owned state.

Both are drained by the kernel in phases N and D.

### 1.5 Boot: declared dependencies and a topological sort

**Today (dx tree).** `master.dm:364-437`:
- sorts subsystems by `init_stage` (FIRST/EARLY/MAIN/LAST);
- orders each stage with `boot_dependency_order()`, which is Kahn's algorithm
  (`boot_dependencies.dm:12`);
- after **each** subsystem, calls `boot_world_services_after(subsystem.type)`, which boots the
  services whose `boot_after` names it (`world_lanes.dm:59-63`);
- boots services with `order_after` depth-first;
- has three units booting others by hand (`atoms.dm:49,51`, `SSair.dm:128`,
  `planet_service.dm:24`);
- has 36 `.initialized` guards;
- flushes machine first-wakes as a special case (`master.dm:448`).

**Target.** There is one DAG, of systems:

```dm
/datum/system
	/// Systems whose initialize() must have finished before ours. Typepaths. The boot DAG.
	var/list/needs
	/// Inverse edges, for a system that must precede ones it doesn't know about (early_assets).
	var/list/needed_by
```

- **Boot runs in two steps:**
  1. The **kernel** boots its 5 subsystems in fixed order: garbage, dbcore, input, verb_manager,
     tgui. This is tg code; nothing gameplay depends on the order inside it.
  2. The kernel instantiates every non-abstract `/datum/system` subtype (the registry is
     `subtypesof()`, with no `GLOBAL_DATUM_INIT` and no hand list). It topo-sorts them with the
     **existing** `boot_dependency_order(nodes, deps, cycle_out)`, keeping its "pop the newest
     ready" tie-break so the order stays deterministic. Then it calls `initialize()` in that order.
- A **cycle** logs, sets `Kernel.boot_cycle`, and fails the `system_boot_dag` unit test, as
  `mc_boot_dependencies` does now.
- A **missing need** (a typepath that is not a system) is a boot error and a test failure.
- **No init stages.** "Early" just means "needs nothing". The config and the DB are kernel steps
  before the DAG. Map loading is the `mapping` system, and anything that needs the map `needs`
  it.
- **One node per fact.** When a unit needs a *side effect* of another (POIs load at the end of
  SSholomaps, and SSair "depends on holomaps" for that reason, `SSair.dm:5-7`), the side effect is
  split into its own system (`/datum/system/pois`) and the dependency names it. The rule: **a
  `needs` entry names the system that establishes what you read.** Comment dependencies are
  banned by lint (`needs` entries require no justification comment; a comment naming a system in
  a `needs` block is flagged).
- **Late members.** Atoms initialize (and join systems through capabilities) before most systems
  run `initialize()`. Membership is recorded immediately. Each member's first `should_run()`
  evaluation is deferred to one bulk pass when the system finishes `initialize()`, through
  `on_members_ready()`. This generalises `machine_first_wakes_flush()` (`machine_pipeline.dm:214-230`)
  to every system and deletes the special case from `master.dm`.
- **Runtime readiness.** Instead of `SSx.initialized` there is `system_ready(/datum/system/x)`, and
  most readers disappear because they are ordered after `x`.
- **Shutdown** runs in reverse topological order through `on_shutdown()`. Today's order is
  subsystems first, then `shutdown_world_services()`.

**Mixed period.** During migration the DAG contains subsystems *and* systems as nodes, so
`boot_after = /datum/controller/subsystem/atoms` becomes `needs = list(/datum/controller/subsystem/atoms)`
and the build stays green. See §6.

### 1.6 Tick budget, failsafe and recovery

- **Budget.** The kernel gets `TICK_LIMIT_RUNNING`. Kernel subsystems run first and are capped at
  a configurable 15%, since input must not wait. Native gets its per-tick Rust budget, as
  `world_budget` does today. The rest goes to D/B/L/R/G. There is no per-system `wait`; `interval`
  plus lane share plus `max_interval` replace it.
- **Isolation.** A system `periodic_step()` that runtimes is caught per call (`report_caught`) and
  counted on the system. After N consecutive faults the kernel parks the system and messages
  admins, instead of looping on the error. The K5 per-lane isolation test covers this.
- **Failsafe.** `/datum/controller/failsafe` watches `Kernel.last_tick` instead of
  `Master.iteration` and keeps its defcon ladder. `Recreate_MC()` becomes `Recreate_kernel()`:
  1. new kernel loop;
  2. **same** system singletons, whose state is on them and not on the loop;
  3. rings re-attached from each system's membership;
  4. deadlines kept in the scheduler.

  This is simpler than per-subsystem `Recover()` copying vars (`SSair.dm:259-271` copies 11
  lists).
- **Profiling.** Cost is accounted per **system** (step, member steps, event handlers, deadlines
  owned). The OM Profiler groups by system, and `metrics()` feeds the stat panel. SSprofiler
  becomes the `profiler` system and reads `metrics()` only.

### 1.7 I/O and waiting: nothing outside the kernel sleeps

**What already exists (b17).** The object model already has non-sleeping I/O:
- `om_io(E, /datum/om/io/<kind>, request..., PROC_REF(on_done), context...)` (`datums/om/io.dm:184`). It returns a job id at once and calls `on_done(result, error, context...)` later. The job is owned by E and cancelled when E is deleted. E and the context are weak handles, and the result is dropped if either is gone. Jobs are polled on the scheduler's I/O lane within budget, which parks when nothing is pending. It has timeouts and per-kind stats. Kinds: `sql`, `http` (plus `test`). 17 files use it.
- `prompt_flow()` / `flow_execute()` (`datums/om/flow_io.dm`). SQL and HTTP inside a prompt flow re-run the entry proc with stored answers instead of waiting. 48 uses.
- `Execute(async = TRUE)` outside a flow is already an error. The blocking `Execute(async = FALSE)` is allowlisted for boot and shutdown only.
- `Destroy()` is already gone from gameplay code. The 9 overrides left are the framework's own teardown engine (`/datum`, `/atom`, `/atom/movable`), the controllers (MC, subsystem, failsafe, config, globals) and `/client`.

**What is left.** About 40 sleeping sites outside tests, in seven groups:

| Group | Sites | Target |
|---|---|---|
| Kernel internals: `stoplag()`, `CHECK_TICK`, the MC and failsafe loops | ~15 | These become the kernel's own code, the only place `sleep` is allowed |
| Player waits: 10 tgui_input modal `wait()` loops (`tgui_input/text.dm:106` and so on), plus 58 legacy callers (18 `tgui_input_*`, 9 `tgui_alert`, 23 `input()`, 8 `alert()`) | 68 | `ask_*` only. The modal resolves a waiter instead of polling |
| I/O not covered by `om_io`: rust-g iconforge jobs (`batched_spritesheet.dm:103,202,262`), the asset-cache client round trip and send pacing | 5 | A new `/datum/om/io/rustg_job` kind. Asset sends become a slice |
| Long work: map reader chunks (`maps/reader.dm:333,336`), the atoms batch, the pathfinder mutex, rogueminer `clean_zone`, POI loads | 7 | A system `periodic_step()` returning `STEP_YIELD` (§1.4) |
| Gameplay leftovers: reflector `UNTIL(!bullet_act_in_progress)` (`reflectors.dm:64,308`; `periodic_step` already has the non-waiting path), ticker `UNTIL(round_end_sound_sent…)` (`ticker.dm:483`), `spawn()` around `animal_nom` (`simple_mob.dm:760`) | 4 | Delete, `om_after_slot`, or a timed action |
| Admin verbs `spawn(N)` | 9 | `om_after()` |
| Vendored TGS | 8 | Leave (vendored) |

The unit tests also have about 60 raw `sleep()` calls. They become one harness helper, `wait_ticks(n)` / `run_until(PROC_REF(cond), timeout)`, which the lint allows only under `unit_tests/`.

**One tension with the approved DX design.** Linear `ask_*` (DX §6) is approved, and it waits: the dispatcher runs the handler with `waitfor = FALSE`, and the modal polls with `stoplag(1)` until the player answers. `prompt_flow` avoids the wait by re-running the proc from the top, but code before the prompt then runs again on every answer, which is a real footgun. The recommendation keeps linear `ask_*` and gives it one kernel primitive:

```dm
/// The only wait outside the kernel. Valid only inside a dispatched handler (already detached);
/// the lint rejects it anywhere else. The kernel resumes the waiter when W resolves, is cancelled,
/// or times out, then ask_*() re-validates the captured context as it does now.
/proc/await(datum/waiter/W)

/datum/waiter
	var/done = FALSE
	var/result
	var/deadline
```

- The kernel keeps one list of open waiters, checked once per pass in the I/O phase. That replaces 10 per-modal `stoplag(1)` loops and every `UNTIL()`.
- A tgui modal calls `waiter_resolve(W, answer)` from its `ui_submit` action. An I/O job does the same from its `on_done`.
- `UNTIL()` and `stoplag()` leave the public API. The `scheduler` lint allowlist shrinks to the kernel folder, `unit_tests/` and vendored TGS.

```dm before
// Before (dbcore.dm:138-142): a sync wrapper that spins the caller
/datum/controller/subsystem/dbcore/proc/run_query_sync(datum/db_query/query)
	run_query(query)
	UNTIL(query.process())
	return query

// After: systems never wait on I/O; they get a callback
om_io(src, /datum/om/io/sql, sql, arguments, PROC_REF(on_rows), ckey)

/datum/system/library/proc/on_rows(list/result, error, ckey)
	if(error)
		return log_sql("library lookup failed for [ckey]: [error]")
	...

// Before (batched_spritesheet.dm:103): polls a rust-g job on the caller's stack
UNTIL((data_out = rustg_iconforge_check(cache_job_id)) != RUSTG_JOB_NO_RESULTS_YET)

// After: the job is an om_io kind; the sheet continues in the callback
om_io(src, /datum/om/io/rustg_job, rustg_iconforge_cache_valid_async(hash, dmis, entries), PROC_REF(on_cache_checked))
```

**Migration position.** This is step 2b of §6: after the kernel exists and before the system conversions. It is small (about 90 sites plus the tests), and it lets the `scheduler` lint go to "kernel folder only" early.

---

## 2. Self-contained systems

### 2.1 The unit

```dm
/// A system: one self-contained part of the game. Plain DM: configuration is type vars, behaviour
/// is overrides. Every non-abstract subtype is instantiated once by the kernel.
/datum/system
	var/name
	var/abstract_type = /datum/system

	// ---- boot
	/// Systems that must finish initialize() before ours (typepaths).
	var/list/needs
	/// Systems that must wait for ours (inverse edge).
	var/list/needed_by

	// ---- time (the same names every datum uses, DX §4)
	/// The system-level cadence (a /datum/cadence), or null for a purely reactive system.
	periodic_cadence = null
	/// Lane for the system's own step, event handlers and member steps.
	var/lane = LANE_SIMULATION
	/// Systems whose step runs before ours in the same pass (same rule as a Rust law's `after`).
	var/list/after

	// ---- members (capabilities bring them, section 2.4)
	/// Cadence for per-member work (member_step), or null when the system has no per-member work.
	var/member_cadence = null

	// ---- contract (read by the boundary lint and by test-build asserts)
	/// Other systems whose api() this one calls.
	var/list/uses
	/// Event types this system raises. Anything else it OM_EMITs is a test-build error.
	var/list/emits

	// ---- owned state lives below, VAR_PRIVATE (DreamChecker rejects access from other types)

/datum/system/proc/initialize()                    // after `needs`; may block (boot only)
/datum/system/proc/on_members_ready()              // after initialize(): first member evaluation
/datum/system/should_run()                         // system cadence gate (DX): FALSE parks it
/datum/system/periodic_step(dt)                    // SHOULD_NOT_SLEEP; STEP_YIELD resumes next tick
/datum/system/proc/member_should_run(atom/A)       // per-member gate, re-evaluated on changed(A)
/datum/system/proc/member_step(atom/A, dt)         // per-member work on member_cadence
/datum/system/proc/on_join(atom/A)                 // membership hooks (capability init/destroy)
/datum/system/proc/on_leave(atom/A)
/datum/system/proc/events()                        // list(/datum/om/event/x = PROC_REF(on_x), ...)
/datum/system/proc/metrics()                       // alist for profiler/stat panel/time_track
/datum/system/proc/on_shutdown()
```

**Why these shapes:**

- **No macros.** A system is a subtype with vars and overrides. The registry finds it through
  `subtypesof(/datum/system)`, the way `build_sys_periodic_defs()` already finds its defs.
- **`events()` is a table-returning proc**, in the DX style. The kernel hooks each entry on
  `OM_WORLD`, or on the members for member events, at boot. It replaces `om_hook(OM_WORLD, …)`
  calls scattered through `initialize()`.
- **The same `should_run()`/`periodic_step()` names** as every other datum: a system *is* a datum
  on a cadence. The world-lane subclass per service (`/datum/om/behaviour/world/X`, 34 of them)
  disappears.
- **Access** is `system(/datum/system/air)`, a proc returning the singleton from an alist keyed by
  type. Hot paths cache it in a local: `var/datum/system/air/air = system(/datum/system/air)`. That
  replaces both `SSair` and `GLOB.x_service`. Nothing is stored in GLOB.

### 2.2 Owned state, API surface and what a system may not touch

A system has three kinds of code:

| Kind | Declared as | Callable by |
|---|---|---|
| **Owned state** | vars on the system, `VAR_PRIVATE` (or `VAR_PROTECTED` for subtypes); per-member state on the member through its capability's `cap_data()` datum or `cap_state` bit | only the system's own procs. DreamChecker enforces vars. Per-member state is written only by the system's procs and the capability's handlers |
| **API** | procs defined in the system folder's `api.dm`: **queries** (`SHOULD_NOT_SLEEP`, read-only by contract) and **commands** (validate, mutate own state, `changed()`, may emit) | any code, including other systems (declared in `uses`) and gameplay atoms |
| **Private** | every other proc on the system, `PRIVATE_PROC(TRUE)` by default via the base type | only the system |

**A system may NOT:**

1. read or write another system's vars. `SSx.var` and `GLOB.x_service.var` have no replacement;
   they are compile-lint errors (`VAR_PRIVATE`) and boundary-lint errors;
2. call a proc on another system that is not in that system's `api.dm`;
3. define procs on another system's type from its own folder. Today this happens in 21 files:
   - the `vg/on_gas_*` handlers in `SSair.dm:289+`
   - 17 SScontracts procs in `modules/contracts/contract_offer.dm`
   - `process_turf_heat()` on SSair in `modules/heat/heat.dm:365`
4. write per-member state that belongs to another system's capability. It uses that capability's
   API or command instead (for example `is_locked(A)` / `cap_set(A, CAP_LOCKED, …)` through the
   lock capability's own procs);
5. poll another system's state on a cadence. It handles that system's event, or reads a published
   world key (`om_world_on_key`);
6. `OM_EMIT` an event type that is not in its `emits`. This is a test-build runtime.

Gameplay atoms follow the same rules toward systems: they call `api.dm` procs and nothing else.

### 2.3 How systems talk

There are three channels, and they already exist in the codebase. The design only restricts
which ones are legal.

| Channel | Use when | Mechanism | Example |
|---|---|---|---|
| **Query** | you need another system's current answer now | its `api.dm` proc | `flight.destination_busy(id)` |
| **Command** | you want another system to change its state | its `api.dm` proc; it validates and owns the write | `round.request_delay_end(user)` |
| **Event** | something happened; zero or more systems may care | `OM_EMIT_WORLD(/datum/om/event/x, args…)`; receivers list it in `events()`; `before/` events can veto | `world_site_released(site)` |
| *(change)* | a member's state changed | `changed(A, channel)` (DX): the kernel re-evaluates `member_should_run(A)` for every system A is in | a machine's `on` toggles and the power system wakes it |
| *(published key)* | world-wide state many systems read and react to (round state, security level, sun per z) | a query to read; `om_world_publish(kind, id, mask)` / `om_world_on_key` to react (`world_watch.dm:88-97`) | `KEY_ROUND_STATE` |

**Rules of thumb:**

- A query must not cause effects. A command must not return internals: it returns a result code
  or a copy.
- An event handler must not synchronously call back into the emitter's commands. The lint flags
  `emits` ↔ `uses` 2-cycles.
- A command that other systems need to react to emits an event. The emitter does **not** call
  those systems itself.
- Telemetry goes only through `metrics()`. The profiler, `time_track` and statpanels hold no
  `uses` edges.

### 2.4 Capabilities: how atoms join systems

The DX stub already does most of this:

```dm
// code/datums/capabilities/capability_ext.dm:12-18
	/// /datum/cap_system types the holder joins while it exists (section 6).
	var/list/joins
/// Systems this capability's holders join, as /datum/cap_system types. Default: `joins`.
/datum/capability/proc/systems()
	return joins
```

```dm
// code/datums/capabilities/capabilities.dm:115-118 (caps_init) and :150-155 (caps_destroy)
	for(var/datum/capability/C as anything in caps)
		C.on_holder_init(src, mapload)
		cap_join_systems(src, C)
...
		C.on_holder_destroy(src)
		cap_leave_systems(src, C)
```

```dm
// code/datums/capabilities/capability_ext.dm:126-158
/datum/cap_system
	var/list/members = list()
/datum/cap_system/proc/join(atom/A)
	members |= A
/datum/cap_system/proc/leave(atom/A)
	members -= A
```

**Target changes:**

1. `/datum/cap_system` becomes `/datum/system`, and `systems()` returns `/datum/system` types.
   `cap_join_systems()` / `cap_leave_systems()` call `S.kernel_join(A)` / `S.kernel_leave(A)`.
2. **Membership storage.** `members |= A` / `members -= A` are O(n) on lists of 10k+ machines.
   The kernel keeps, per system, a `members` list plus an `alist` of member → index, and removes by
   swap-remove in O(1). Each entity's OM record keeps the ids of the systems it is in, so a
   `changed(A)` knows which `member_should_run()` to re-evaluate. The destroy transaction calls
   `caps_destroy()`, so leaving is automatic, as it is today.
3. **Per-type tables.** `systems()` is static data, collected once per type:
   `type_list(A, /proc/caps_systems_of)`. The same capability on 5,000 floor lights costs one
   table, not 5,000.
4. **Standard capabilities name their systems.** For example:

```dm
/datum/capability/powered
	joins = list(/datum/system/power)            // draws power: the power system bills it
/datum/capability/gas_device
	joins = list(/datum/system/atmos_devices)
/datum/capability/breathes
	joins = list(/datum/system/life)             // on /mob/living through its capabilities()
```

5. **Non-capability membership.** For datums that aren't atoms (vessels, sites, plans), the owning
   system keeps its own owned list (`VAR_PRIVATE`). Capabilities are for atoms.
6. **Mobs.** Mobs get `capabilities()` like any atom: `/mob/living/capabilities()` returns
   `list(living_body())`, and `living_body()` is a preset whose capability `joins` Life,
   ai_brain and so on. This retires `/datum/om/decl/living` (`life_om.dm:7-14`). The Life stage
   variants still resolve per mob type, as today.
7. **Hand-maintained rosters disappear.** `/datum/om/decl/pipeline_machines` (`machine_pipeline.dm:14-160`)
   is a hand list of about 150 machine types, checked complete by `pollers_lint.py`. It becomes
   `powered` / `machine_work` capabilities on the types, and the list is derived.

### 2.5 Module boundary: folder layout and CI enforcement

Each system lives in **one folder**. That is the module.

```
code/modules/expedition/          # the folder IS the system's module
  _expedition.dm                  # /datum/system/expedition: needs, cadence, lane, uses, emits, VAR_PRIVATE state
  api.dm                          # the ONLY procs other code may call: queries + commands
  events.dm                       # /datum/om/event/expedition/* (the types in `emits`)
  capabilities.dm                 # capabilities whose systems() include this system (if any)
  site.dm, generation.dm, ...     # private implementation (procs on its own types)
```

**Rules**, enforced by `tools/ci/system_boundary_lint.py` with a shrink-only baseline started from
the audit's counts:

| Rule | Check | Baseline today |
|---|---|---|
| B1 | no `SSx.<var>` / `GLOB.<x>_service.<var>` / `system(...).<var>` outside the owner's folder | 1,657 accesses (242 writes) |
| B2 | `system(/datum/system/X).proc()` from outside X's folder must name a proc defined in X's `api.dm` | new |
| B3 | no `/datum/system/X/...` proc definitions outside X's folder | 21 files (SS procs) |
| B4 | X calls Y's API only if `Y in X.uses` | new |
| B5 | no cycles in `needs`, and none in `uses` + `events()` 2-cycles | 4 SCCs |
| B6 | `OM_EMIT*` types under X's folder ⊆ `emits` | new |
| B7 | a system folder has `api.dm` iff other folders call it | new |

DreamChecker's `VAR_PRIVATE` / `PRIVATE_PROC` (already used 164 + 142 times,
`code/__spaceman_dmm.dm:17`) enforce B1 and B2 on the type itself at lint time. The Python lint
covers what DreamChecker can't see: folder ownership, `uses`, event lists and cross-folder proc
definitions.

**Allowlist.** Admin verbs and unit tests may read private state. They are tagged with
`// ALLOW(system_boundary): reason` through the existing tag registry
(`tools/ci/allow_annotations.py`), and tests use a `system_debug(X)` accessor that exists only in
`UNIT_TESTS` builds.

---

## 3. Before/after, with real code

**How to read the quotes.** Every "before" quote is verbatim from the dx-framework worktree. Some
are abridged with `...`, but the kept lines are unchanged. The "after" blocks are the target code.

### 3.1 The kernel: MC loop vs kernel tick

**Before** (`code/controllers/master.dm`):

```dm
// master.dm:614-640 — per-subsystem timing state rebuilt on every MC (re)start
	for (var/thing in subsystems)
		var/datum/controller/subsystem/SS = thing
		if (SS.flags & SS_NO_FIRE)
			continue
		...
		if ((SS.flags & (SS_TICKER|SS_BACKGROUND)) == SS_TICKER)
			tickersubsystems += SS
			// Timer subsystems aren't allowed to bunch up, so we offset them a bit
			timer += TICKS2DS(rand(0, 1))
			SS.next_fire = timer
			continue
```

```dm before
// master.dm:936-966 — CheckQueue: a second cadence model (wait/next_fire/postponed/KEEP_TIMING)
	for (var/thing in subsystemstocheck)
		...
		if (SS.next_fire > world.time)
			continue
		...
		if ((SS_flags & (SS_TICKER|SS_KEEP_TIMING)) == SS_KEEP_TIMING && SS.last_fire + (SS.wait * 0.75) > world.time)
			continue
		if (SS.postponed_fires >= 1)
			SS.postponed_fires--
			SS.update_nextfire()
			continue
		SS.enqueue()
```

```dm
// master.dm:1015-1045 — RunQueue: a second budget model (priority fractions)
			if (queue_node_priority >= 0 && current_tick_budget > 0 && current_tick_budget >= queue_node_priority)
				//Give the subsystem a precentage of the remaining tick based on the remaining priority
				tick_precentage = tick_remaining * (queue_node_priority / current_tick_budget)
			...
			current_ticklimit = round(TICK_USAGE + tick_precentage)
			...
			var/state = queue_node.ignite(queue_node_paused)
```

```dm
// controllers/subsystems/behaviours.dm:29-34 — the real scheduler, as ONE of the MC's subsystems
/datum/controller/subsystem/behaviours/fire(resumed)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return
	var/start = TICK_USAGE
	last_done = sched.run_pass(Master.current_ticklimit)
```

**After** (`code/controllers/kernel/kernel.dm`):

```dm
/// The kernel loop: one budgeted pass per tick. The OM scheduler is the engine; the kernel owns the
/// host duties the MC had (budget, failsafe heartbeat, runlevels) and the five kernel subsystems.
/datum/controller/kernel/proc/loop()
	while(TRUE)
		last_tick = world.time
		var/limit = TICK_LIMIT_RUNNING
		if(TICK_USAGE > TICK_LIMIT_MC)              // BYOND resumed us late: yield this tick
			sleep(world.tick_lag) // ALLOW(scheduler): kernel host loop
			continue
		run_kernel_subsystems(limit * KERNEL_SHARE)  // input, verb_manager (+ dbcore pump, tgui transport)
		sched.native_step()                          // the ONE Rust driver (section 3.3)
		sched.run_pass(limit)                        // deadlines, borrow, lanes, leftovers (unchanged)
		run_garbage(limit)                           // tg GC, whatever is left, floor per second
		record_performance_tick(TICK_USAGE)
		sleep(world.tick_lag) // ALLOW(scheduler): kernel host loop

/// Kernel subsystems keep tg's /datum/controller/subsystem shape (fire(resumed), Recover()) but
/// run in fixed order with a cap: no priority queue, no next_fire bookkeeping for gameplay.
/datum/controller/kernel/proc/run_kernel_subsystems(cap)
	var/stop = TICK_USAGE + cap
	for(var/datum/controller/subsystem/SS as anything in kernel_subsystems)
		if(SS.can_fire && SS.due())
			SS.ignite(FALSE)
		if(TICK_USAGE > stop)
			return
```

**What goes away:**
- `CheckQueue`, the priority fractions in `RunQueue`, `SoftReset`'s runlevel lists, and
  `runlevel_sorted_subsystems` (the kernel five fire every runlevel);
- the SSbehaviours trampoline;
- `boot_world_services_after` and `machine_first_wakes_flush` in `Initialize`.

Performance ring-buffer telemetry and `AttemptProfileDump` move over unchanged. Expected size of
`master.dm`: about 400 lines (the kernel five plus failsafe glue).

### 3.2 Boot: stage loop plus service hooks plus hand boots vs one DAG

**Before:**

```dm before
// master.dm:428-448
	for (var/current_init_stage in 1 to INITSTAGE_MAX)
		for (var/datum/controller/subsystem/subsystem in stage_sorted_subsystems[current_init_stage])
			subsystem.init_order = evaluated_order
			evaluated_order++
			init_subsystem(subsystem)
			boot_world_services_after(subsystem.type)
			CHECK_TICK
		...
	// Every machine that materialized during init arms its wakes now, in one pass (machine_pipeline.dm).
	machine_first_wakes_flush()
```

```dm
// controllers/subsystems/atoms.dm:46-51 — a subsystem booting services by hand
/datum/controller/subsystem/atoms/Initialize()
	EXPIRY_STAMP(src, init_start_time, CLOCK_WORLD)
	// Mapload resleeving machines register with the transcore databases (was a SStranscore dependency).
	boot_world_service(GLOB.transcore_service)
	// Planets register their floors and walls as turfs initialize (fold wave F4; was SSplanets).
	boot_world_service(GLOB.planet_service)
```

```dm before
// ATMOSPHERICS/SSair.dm:1-8, 124-128 — a dependency that is really on a side effect, plus a hand boot
SUBSYSTEM_DEF(air)
	name = "Atmospherics"
	dependencies = list(
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/atoms,
		// The machine world service initializes at the top of Initialize() (it was
		// SSmachines, which depended on points_of_interest; POIs now load at the end of SSholomaps).
		/datum/controller/subsystem/holomaps,
	)
...
/datum/controller/subsystem/air/Initialize()
	...
	GLOB.machine_service.initialize()
```

**After:**

```dm
/datum/system/transcore
	needs = list(/datum/system/mapping)           // atoms' resleevers join it via capability, before it inits
/datum/system/planets
	needs = list(/datum/system/mapping)
/datum/system/atoms
	needs = list(/datum/system/mapping, /datum/system/jobs, /datum/system/transcore, /datum/system/planets)
/datum/system/pois                                 // split out of holomaps: the side effect gets a node
	needs = list(/datum/system/atoms)
/datum/system/machines
	needs = list(/datum/system/atoms, /datum/system/pois, /datum/system/native)
/datum/system/atmos_pipes
	needs = list(/datum/system/atoms, /datum/system/gas_registry, /datum/system/machines)

// code/controllers/kernel/boot.dm
/datum/controller/kernel/proc/boot_systems()
	var/list/nodes = list()
	var/list/deps = list()
	for(var/path in subtypesof(/datum/system))
		var/datum/system/proto = path
		if(initial(proto.abstract_type) == path)
			continue
		var/datum/system/S = systems_by_type[path] || (systems_by_type[path] = new path)
		nodes += S
	for(var/datum/system/S as anything in nodes)
		deps[S] = resolve_needs(S)                  // needs + others' needed_by; unknown path = boot error
	var/list/cycle = list()
	var/list/order = boot_dependency_order(nodes, deps, cycle)   // the existing Kahn sort
	if(length(order) != length(nodes))
		boot_cycle = jointext(cycle, " -> ")
		stack_trace("KERNEL: system dependency cycle: [boot_cycle]")
	for(var/datum/system/S as anything in order)
		S.initialize()
		S.ready = TRUE
		S.on_members_ready()                        // first should_run() of members that joined early
		attach_rings(S)                             // system cadence + member cadence rings
		CHECK_TICK
```

**What changes:**
- `boot_world_service()`, `boot_after`, `order_after`, `init_stage` and the three hand boots go.
- `machine_first_wakes_flush()` becomes `/datum/system/machines/on_members_ready()`.

### 3.3 SSair, SSvg and heat vs native plus split atmos systems

**Before:**

```dm before
// controllers/subsystems/vg.dm:74-77 — Rust driver #1 (0.5 s)
/datum/controller/subsystem/vg/fire(resumed)
	vg_world_tick(wait / (1 SECONDS))
	vg_entity_tick_all()
	vg_drain_events()
```

```dm before
// ATMOSPHERICS/SSair.dm:183-257 (abridged) — driver #2: a phase machine that also drains events,
// steps heat, and pushes a debug UI
/datum/controller/subsystem/air/fire(resumed = FALSE)
	...
	if(initialized)
		vg_atmos_callback_handle(min(max(SSAIR_REMAINING_MS, 1), 3))
	if(currentpart == SSAIR_PIPENETS || !resumed)
		...
		process_pipenets(resumed)
	...
	if(currentpart == SSAIR_TURFS)
		...
		vg_drain_events()
		gas_frames++
	...
	if(currentpart == SSAIR_HIGHPRESSURE)
		...
		process_high_pressure_delta(resumed)
	...
	if(currentpart == SSAIR_SUPERCONDUCTIVITY)
		process_turf_heat()
		resumed = FALSE
	currentpart = SSAIR_PIPENETS
	SStgui.update_uis(SSair) //Lightning fast debugging motherfucker
```

```dm before
// modules/heat/heat.dm:365-369 — the heat domain stepped as an SSair proc defined in another folder
/datum/controller/subsystem/air/proc/process_turf_heat()
	var/now = world.time
	var/elapsed = heat_last_tick ? (now - heat_last_tick) / (1 SECONDS) : wait / (1 SECONDS)
	heat_last_tick = now
	if(vg_heat_tick(elapsed) > 0)
		dispatch_heat_wakes()
```

```dm before
// ATMOSPHERICS/SSair.dm:289-296 — an SSvg proc, defined in SSair's file, writing SSair's counters
/datum/controller/subsystem/vg/on_gas_cell_reaction_ready(cell, reaction)
	SSair.gas_events_last++
	var/turf/open/T = vg_turf_of(cell)
	if(!istype(T))
		return
	SSair.gas_reactions_last++
	if(T.air)
		T.air.react(T)
```

```dm before
// datums/om/world_watch.dm:196-209 — driver #3: the OM scheduler steps the Rust wheel every tick
/datum/om/scheduler/proc/world_step()
	...
	var/list/wakes = vg_world_step(tick, world_budget * elapsed)
```

**After** (four folders: `code/modules/native/`, `code/ATMOSPHERICS/gas/`,
`code/ATMOSPHERICS/pipes/`, `code/modules/heat/`):

```dm
// code/modules/native/_native.dm — the ONE Rust driver; runs as kernel phase N, not on a lane
/datum/system/native
	name = "Native (Rust world)"
	emits = list(/datum/om/event/native/gas_reaction_ready, /datum/om/event/native/gas_visual,
		/datum/om/event/native/spacewind, /datum/om/event/native/power_region)
	VAR_PRIVATE/last_tick = 0

/datum/system/native/proc/kernel_step()            // called by sched.native_step(), once per tick
	var/elapsed = (world.time - last_tick) / (1 SECONDS)
	last_tick = world.time
	vg_world_tick(elapsed)                          // gas + power laws (was SSvg) // ALLOW(doc_snippets): the driver entry points as designed; the final names follow the Rust bindings
	vg_heat_tick(elapsed)                           // heat frames (was SSair superconductivity) // ALLOW(doc_snippets): the driver entry points as designed; the final names follow the Rust bindings
	sched.world_step()                              // timers, keys, rates, native watches (unchanged) // ALLOW(doc_snippets): the driver entry points as designed; the final names follow the Rust bindings
	native_dispatch(vg_drain_events())              // the ONLY drain; typed events -> OM_EMIT_WORLD

/datum/system/native/metrics()
	return alist("gas" = vg_gas_stats(), "heat" = vg_heat_stats(), "laws" = vg_world_laws())
```

```dm
// code/ATMOSPHERICS/gas/_gas_reactions.dm
/datum/system/gas_reactions
	needs = list(/datum/system/gas_registry)
	lane = LANE_SIMULATION
	VAR_PRIVATE/reactions_last = 0

/datum/system/gas_reactions/events()
	return list(/datum/om/event/native/gas_reaction_ready = PROC_REF(on_reaction_ready))

/datum/system/gas_reactions/proc/on_reaction_ready(cell, reaction)
	EVENT_HANDLER
	var/turf/open/T = vg_turf_of(cell)
	if(istype(T) && T.air)
		reactions_last++
		T.air.react(T)

/datum/system/gas_reactions/metrics()
	return alist("reactions" = reactions_last)
```

```dm
// code/ATMOSPHERICS/pipes/_atmos_pipes.dm — pipenets only; members come from the pipe capability
/datum/system/atmos_pipes
	needs = list(/datum/system/atoms, /datum/system/gas_registry, /datum/system/machines)
	periodic_cadence = CADENCE_HALF_SECOND
	after = list(/datum/system/native)
	VAR_PRIVATE/list/networks = list()              // was SSair.networks + START_PROCESSING_PIPENET

/datum/system/atmos_pipes/periodic_step(dt)
	return process_pipenets()                       // STEP_YIELD while budget runs out

// code/ATMOSPHERICS/pipes/api.dm
/datum/system/atmos_pipes/proc/add_network(datum/pipe_network/N)     // command (was the macro)
/datum/system/atmos_pipes/proc/network_count()                        // query
```

**What changes:**
- `spacewind` becomes its own system that handles `native/spacewind` and drains its delta list on
  a 0.5 s cadence.
- `heat` becomes a facade-only system (`heat_watch_set()`, `get_temperature()`) with no step.
- The debug UI stops being pushed from `fire()`. The atmos panel reads `metrics()` on the
  presentation lane.
- `SSvg` keeps only the binding identity table (`bind_datum`, `entity_lookup`) as kernel library
  code, plus a `vg_reconciler` system (`LANE_BACKGROUND`, 0.5 s, 5 atoms per step).
- **Edges removed:**

| Edge | Sites |
|---|---|
| air→vg | 1 |
| vg→air | 6 |
| air→machines | 1 |
| air→tgui | 1 |
| time_track→air | 17 |
| profiler→air | 20 |
| explosions→air | 1 |
| expedition→air | 2, replaced by an api call `atmos_pipes`/`multiz_air.add_level(z)` |

### 3.4 Machines and power: one service doing three jobs vs systems per job

**Before:**

```dm
// game/machinery/machine_service.dm:10-13, 56-74 — gas watch dispatch + atmos pump commit + power step
GLOBAL_DATUM_INIT(machine_service, /datum/system/machines, new)
/datum/system/machines
	name = "Machines"
	lane = /datum/om/behaviour/world/machines
...
/datum/system/machines/service_step(resumed)
	...
	var/complete = wake_dirty_gas_subscribers(TRUE)
	if(complete)
		flush_pump_transfers()
	...
	var/power_started = TICK_USAGE
	process_power()
```

```dm
// game/machinery/machine_pipeline.dm:14-30, 160-168 — a hand roster of ~150 types + its own vocabulary
/datum/om/decl/pipeline_machines
	of = list(
		/obj/machinery/recharger,
		/obj/machinery/cell_charger,
		/obj/machinery/power/apc,
		...
		/obj/machinery/vr_sleeper,
	)
	behaviours = list(/datum/om/pipeline/machine)
```

The machine pipeline's "step" stage (deleted; a machine's work is `started_work()` now) started and stopped a machine's `machine_step()` through `MACHINE_WAKE()` and a `step_active` field.

```dm
// game/machinery/floodlight.dm:17, 29-32 — a fourth start/stop vocabulary on top
DECLARE_PERIODIC_WHILE(/obj/machinery/floodlight, MACHINE_PIPELINE, "on")
...
/obj/machinery/floodlight/machine_step()
	if(!cell || (cell.charge < (use * CELLRATE)))
		turn_off(1)
		return PROCESS_KILL
```

```dm
// ATMOSPHERICS pumps reach into the machine service's queue directly (machine_service.dm:85)
/datum/system/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, ...)
```

**After:**

```dm
// A floodlight is ordinary DX: a cadence, a gate, a step. No roster entry, no MACHINE_WAKE.
/obj/machinery/floodlight
	periodic_cadence = CADENCE_SLOW

/obj/machinery/floodlight/capabilities()
	. = ..()
	. += floor_machine()                          // includes powered(): joins /datum/system/power
	. += slot(nameof(cell), /obj/item/cell, behind = COVER)

/obj/machinery/floodlight/should_run()
	return on && cell && cap_powered()          // re-evaluated on changed(); parks when FALSE

/obj/machinery/floodlight/periodic_step(dt)
	if(cell.charge < use * CELLRATE)
		turn_off(TRUE)                          // a TRACKED set_on(FALSE) -> should_run() FALSE -> parked
		return
	cell.use(use * CELLRATE)
```

```dm
// code/modules/power/_power.dm — the Rust power domain's DM side, members from `powered`
/datum/system/power
	needs = list(/datum/system/native, /datum/system/atoms)
	periodic_cadence = CADENCE_SLOW
	after = list(/datum/system/native)
	VAR_PRIVATE/alist/power_grids = alist()       // was machine_service.power_grids (12 external reads)

/datum/system/power/periodic_step(dt)
	power_grid_refresh()                          // reads vg_power_region_read (power_grid.dm)

/datum/system/power/events()
	return list(/datum/om/event/native/power_region = PROC_REF(on_region))

// code/modules/power/api.dm
/datum/system/power/proc/region_of(atom/A)                   // query
/datum/system/power/proc/material_overlay_for(region_id)     // query (was power_material_overlays poke)

// code/ATMOSPHERICS/devices/_atmos_devices.dm — the pump batch belongs to atmos, not "machines"
/datum/system/atmos_devices
	needs = list(/datum/system/atmos_pipes)
	periodic_cadence = CADENCE_SLOW
	after = list(/datum/system/atmos_pipes)
	VAR_PRIVATE/list/pending_pump_transfers = list()
/datum/system/atmos_devices/periodic_step(dt)
	flush_pump_transfers()
// api.dm: /datum/system/atmos_devices/proc/queue_pump_transfer(...)   // command

// code/modules/atmos_watch/_gas_watch.dm — gas dependency wakes: native dirty-set -> watches
/datum/system/gas_watch
	needs = list(/datum/system/native)
	periodic_cadence = CADENCE_SLOW
	after = list(/datum/system/native)
/datum/system/gas_watch/periodic_step(dt)
	return wake_dirty_gas_subscribers()           // STEP_YIELD mid-batch, as today
```

**What changes:**
- **The machine pipeline shrinks to two jobs:**
  - the capability-driven periodic ring;
  - per-type power-mode stages (`power/recharger`, `power/apc`), which become `member_step()`
    variants on `/datum/system/power` for types whose `powered` capability declares a
    `power_mode()` proc.
- `present` stages go, because DX `draw()` plus refresh replace `update_icon()` stages.
- **Deleted:**
  - `machine_step()`, 227 sites, renamed to `periodic_step(dt)`
  - `MACHINE_WAKE`/`MACHINE_SLEEP` (130), replaced by `changed()` and `should_run()`
  - `step_active`, `step_waiting_power`, `speed_process` (a cadence choice, `CADENCE_FAST`)
  - `DECLARE_PERIODIC_WHILE(…, MACHINE_PIPELINE, …)`
  - the roster, derived from capabilities instead

### 3.5 Mobs and Life: service plus decl plus 4 pipelines vs one Life system

**Before:**

```dm
// modules/mob/living/life/life_om.dm:7-14, 22-35
/datum/om/decl/living
	of = /mob/living
	behaviours = list(
		/datum/om/pipeline/life,
		/datum/om/pipeline/life_derive,
		/datum/om/pipeline/life_present,
		/datum/om/pipeline/life_vision,
	)
...
/datum/om/pipeline/life
	name = "life"
	every = LIFE_CYCLE
	step_interval = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	relevance = list(OM_PARK, null, null, null)
	stages = list(/datum/om/stage/life)
```

```dm
// modules/mob/living/carbon/human/life.dm:2117-2135 — a stage: idle() + rewake_delay() + perform()
/datum/om/stage/life/heartbeat
	order = LIFE_PHASE_TAIL + 240
	name = "heartbeat"
	wake_on = CHANGE_MOB_HEALTH | CHANGE_MOB_LOC | CHANGE_MOB_CLIENT
	run_if = LIFE_RUN_IF_LIVE_BIOLOGY
	of = /mob/living/carbon/human
...
/datum/om/stage/life/heartbeat/idle(mob/living/carbon/human/self)
	if(!self.client || self.pulse == PULSE_NONE)
		return TRUE
	return self.pulse < PULSE_2FAST && self.shock_stage < 10 && !istype(get_turf(self), /turf/space)

/datum/om/stage/life/heartbeat/rewake_delay(mob/living/carbon/human/self)
	return 4 SECONDS
```

```dm
// modules/mob/mob_service.dm:17-19, 82-89 — the "mobs" service: a DECLARE_REPEAT, and death -> SSticker internals
OM_FIELD(/datum/system/mobs, profiling, FALSE, CHANGE_DATUM_A)
DECLARE_REPEAT(/datum/system/mobs, 2 MINUTES, dump_profile, "profiling")
...
/datum/system/mobs/proc/report_death(mob/living/L)
	...
	if(!SSticker || !SSticker.mode)
		return
	SSticker.mode.check_win()
```

**After:**

```dm
// code/modules/mob/living/life/_life.dm
/datum/system/life
	name = "Life"
	needs = list(/datum/system/atoms)
	member_cadence = CADENCE_LIFE                 // fixed step, bio clock, relevance park: cadence data
	lane = LANE_SIMULATION

/// The ordered stage families (the same 66 /datum/om/stage/life families, variants per mob type).
/datum/system/life/proc/stages()
	return list(/datum/om/stage/life)

/datum/system/life/member_should_run(mob/living/L)
	return L.loc && !L.transforming && life_any_stage_wants(L)   // == today's "not every stage idle"

/datum/system/life/member_step(mob/living/L, dt)
	run_life_frame(L, dt)                         // the existing pipeline runner, unchanged inside

// The stage keeps its shape; only the names align with DX.
/datum/om/stage/life/heartbeat/should_run(mob/living/carbon/human/self)
	return self.client && self.pulse != PULSE_NONE && (self.pulse >= PULSE_2FAST || self.shock_stage >= 10 || istype(get_turf(self), /turf/space))

/datum/om/stage/life/heartbeat/periodic_step(mob/living/carbon/human/self, datum/om/frame/life/ctx)
	...                                          // was perform(); returns rewake_in(4 SECONDS) when a raw pulse write is possible
```

```dm
// derive / present / vision are the same system's other passes, not three more pipelines:
/datum/system/life_present
	needs = list(/datum/system/life)
	lane = LANE_PRESENTATION
	member_cadence = CADENCE_PRESENT              // min_interval LIFE_PRESENT_MIN_INTERVAL, has_client gate
/datum/system/life_present/member_should_run(mob/living/L)
	return L.client && life_present_dirty(L)

// Death reporting: the mobs service stops reaching into the round's game mode.
/mob/living/proc/death(gibbed)
	...
	PUBLISH_LEGACY(OM_WORLD, /datum/notice/world_mob_death, src, gibbed)   // exists today (mob/death.dm:125)

/datum/system/round/events()
	return list(/datum/om/event/world_mob_death = PROC_REF(on_mob_death))   // check_win() lives here

/datum/system/death_stats                          // was mob_service's DB half
	uses = list(/datum/system/db)
/datum/system/death_stats/events()
	return list(/datum/om/event/world_mob_death = PROC_REF(queue_death_row))
/datum/system/death_stats/periodic_step(dt)        // CADENCE_SLOW; should_run() = length(rows)
	system(/datum/system/db).mass_insert(format_table_name("death"), take_rows())
```

**What changes:**
- `/datum/om/decl/living` and `/datum/system/mobs` are deleted.
- `DECLARE_REPEAT(... dump_profile ...)` moves into the kernel profiler, which is where stage cost
  already lives (`sched.stage_cost`).
- The mobs→ticker edge becomes an event.

### 3.6 Expedition and flight: a two-cycle vs a DAG

**Before:**

```dm
// modules/flight_operations/flight_controller.dm:6-12, 50-58
/datum/system/flight
	name = "Flight Operations"
	lane = /datum/om/behaviour/world/flight
	// The old subsystem depended on SSshuttles (it registers SSshuttles.ships); boot right after it.
	boot_after = /datum/controller/subsystem/shuttles
	// rebuild_registry() registers any live expedition sites.
	order_after = list(/datum/system/expedition)
...
	for(var/key in GLOB.expedition_service?.sites)
		var/datum/expedition_site/site = GLOB.expedition_service.sites[key]
		if(istype(site))
			register_expedition(site)
```

```dm
// modules/expedition/expedition_controller.dm:158-170, 249 — expedition reads and WRITES flight's indexes
	var/datum/flight_destination/destination = GLOB.flight_service?.destinations[site.flight_destination_id]
	if(LAZYLEN(destination?.active_plans))
		to_chat(user, span_warning("The assignment cannot be abandoned while a flight plan is using it."))
		return FALSE
	...
			GLOB.flight_service?.unregister_destination(site.flight_destination_id)
...
			GLOB.flight_service.destination_by_target[REF(site.overmap_sector())] = destination.id
```

**After:**

```dm
// code/modules/expedition/_expedition.dm
/datum/system/expedition
	needs = list(/datum/system/mapping)
	periodic_cadence = CADENCE_SLOW
	emits = list(/datum/om/event/expedition/site_opened, /datum/om/event/expedition/site_released,
		/datum/om/event/expedition/site_moved)
	uses = list(/datum/system/flight)             // one query: destination_busy()
	VAR_PRIVATE/list/sites = list()
	VAR_PRIVATE/list/free_z = list()

/datum/system/expedition/should_run()
	return length(teardown_z) || has_generation_queued()   // was on_demand + has_work()

// code/modules/expedition/api.dm
/datum/system/expedition/proc/site(id)                    // query
/datum/system/expedition/proc/open_sites()                // query: a copy
/datum/system/expedition/proc/abandon(mob/user, datum/flight_vessel/vessel)   // command
	var/datum/expedition_site/site = vessel?.active_expedition()
	if(!site || QDELETED(site))
		return FALSE
	if(system(/datum/system/flight).destination_busy(site.flight_destination_id))
		return refuse(user, "The assignment cannot be abandoned while a flight plan is using it.")
	if(site.z_level > 0 && players_on_z(site.z_level))
		return refuse(user, "The assignment cannot be abandoned while crew remain at the site.")
	rel_clear(vessel, "active_expedition")
	release_site(site, "assignment abandoned")    // emits site_released; flight unregisters its OWN destination
	return TRUE

// code/modules/flight_operations/_flight.dm
/datum/system/flight
	needs = list(/datum/system/shuttles)          // no order_after on expedition any more
	periodic_cadence = CADENCE_SECOND
	uses = list(/datum/system/expedition, /datum/system/shuttles)
	VAR_PRIVATE/list/destinations = list()
	VAR_PRIVATE/list/destination_by_target = list()

/datum/system/flight/events()
	return list(
		/datum/om/event/expedition/site_opened = PROC_REF(register_expedition),
		/datum/om/event/expedition/site_moved = PROC_REF(retarget_expedition),   // replaces the external write
		/datum/om/event/expedition/site_released = PROC_REF(unregister_expedition),
	)

/datum/system/flight/initialize()
	rebuild_registry()
	for(var/datum/expedition_site/site as anything in system(/datum/system/expedition).open_sites())
		register_expedition(site)                 // replay: works whichever booted first
```

**What changes:**
- The cycle becomes flight→expedition (queries) plus expedition events that flight handles.
- `order_after` goes.
- The external write into `destination_by_target` (`expedition_controller.dm:249`) becomes flight's
  own handler.
- **Totals:** 13 call sites across both files become 2 API calls plus 3 events.

### 3.7 Timers and periodic work: SStimer and SSprocessing successors vs cadence plus should_run

SStimer and SSprocessing are already gone (b17). Their successors are the five start/stop
vocabularies below, and this is what they collapse to.

**Before:**

```dm
// game/gamemodes/nuclear/pinpointer.dm:21-22, 38 — OM_FIELD + DECLARE_PERIODIC_WHILE + periodic_step()
OM_FIELD(/obj/item/pinpointer, active, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/pinpointer, PERIODIC_SLOW, "active")
...
/obj/item/pinpointer/periodic_step()
```

```dm
// game/machinery/magnet.dm:31 — DECLARE_REPEAT with a string-named delay proc
DECLARE_REPEAT(/obj/machinery/magnetic_module, "magnet_delay", magnetic_process, "on")
```

```dm
// datums/om/periodic.dm:33-47 — the imperative start the declarations wrap
/proc/_om_periodic_start(datum/E, P)
	...
	if(!sys_periodic_allows(E, P))
		return FALSE
	E.periodic_pipe = P
	E.datum_flags |= DF_ISPROCESSING
	if(om_attached(E, P))
		om_wake(E, P)
	else
		om_attach(E, P)
```

(The world lanes of the survey, `datums/om/world_lanes.dm`, are gone: the world services are systems with `every()` work items, phase 1S.)

```dm
// datums/behaviours/radiation_countdown.dm:22 — a sixth: a self re-arming timer
	after(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear), key = "radiation_countdown")
```

**After:** one vocabulary for items, machines, mobs and systems alike.

```dm
/obj/item/pinpointer
	var/active = FALSE
	periodic_cadence = CADENCE_SLOW
TRACKED(/obj/item/pinpointer, active, CHANGE_SETTINGS)

/obj/item/pinpointer/should_run()
	return active

/obj/item/pinpointer/periodic_step(dt)
	...

/obj/machinery/magnetic_module
	periodic_cadence = CADENCE_CUSTOM
/obj/machinery/magnetic_module/periodic_interval()   // a proc when it varies, a var when it doesn't
	return magnet_delay()
/obj/machinery/magnetic_module/should_run()
	return on
/obj/machinery/magnetic_module/periodic_step(dt)
	magnetic_process()

// A one-shot stays om_after / om_after_slot / timed_set (DX §7):
/mob/living/proc/start_radiation_countdown()
	timed_set(src, nameof(radiation_countdown), TRUE, for_time = TIME_UNTIL_DELETION)
```

**Kernel internals.** `periodic_cadence` → ring, `should_run()` → park/unpark (already
`refresh_periodic()`, `refresh.dm:161-170`), and a system's cadence is the same ring on the system
singleton. `_om_periodic_start`, `sys_periodic_allows`, `/datum/sys_periodic_def` (and the 216
declarations), the world-lane subclasses, `on_demand`/`demand()`/`has_work()` and
`om_after_stagger`/`om_after_drift` are deleted.

### 3.8 SSticker and the round lifecycle (the 6-node cycle)

Kept short, since the audit §7.2 has the full sketch. The current code has these entanglements:
- `ticker.dm:154-157` reads `GLOB.emergency_shuttle_service.returned()`.
- `ticker.dm:171` calls `GLOB.vote_service.start_vote(...)`.
- `ticker.dm:308-311` calls `SSjob.reset_occupations()/divide_occupations()`.
- `job.dm:402` reads `SSticker.mode.disabled_jobs`.
- There are 90 external `SSticker.mode` reads.

**Target** (`/datum/system/round`):
- It publishes `KEY_ROUND_STATE`.
- It emits `world_round_setup`/`started`/`ending`/`ended`.
- It exposes `api.dm` queries `state()` and `mode_view()` (read-only), plus commands
  `request_delay_end()` and `request_reboot()`.
- Other systems react:
  - jobs handles `world_round_setup`
  - antag handles `world_roles_assigned`
  - emergency_shuttle emits `world_evac_returned`, which round handles
  - vote handles `world_round_duration`
- The SCC becomes a DAG.

---

## 4. Dependency graph: before and after

### 4.1 Before

Measured on b17: 73 world-level units, 63 direct edges (225 sites), 4 SCCs. Showing cycles and
hubs only:

```
          ┌──────────── SSprofiler ──(20)──► SSair ◄──(17)── time_track ◄──(8)── statpanels
          │                 │                 ▲ │ ▲
          │               (20)               (6)(1)(2)
          │                 ▼                 │ ▼ │
          │           machine_service ◄─(1)─ SSvg   expedition ◄──(4)──┐
          │                                          │  (9)            │
          │                                          └────► flight ────┘ (cycle)
          │                                                   │(7)
          │                                                   ▼
          │                                               SSshuttles
          ▼
   SSticker ◄──(6)──► SSjob          SSlighting ◄──(2)── planets    (cycle)
    │  ▲  ▲ ▲             ▲             └────(5)──────────►▲
    │  │  │ └(3)─ emergency_shuttle ◄┘(5)
    │  │  └(2)── SScontracts ◄──(7)── supply ◄──(2)── SSticker        (6-node SCC:
    │  └───(1)── antag ──(1)──► SSjob                                   ticker, job, contracts,
    └──(1)──► vote                                                       antag, e_shuttle, supply)

   SSatoms ──► transcore, planets (hand boots)        SSair ──► machine_service (hand boot)
   Everything ──► SStgui (49 modules), SSticker (33), SSjob (22), SSair (18), supply (18) ...
```

### 4.2 After

Target: about 70 systems. The only edges are:
- `needs` (boot)
- `uses` (API calls)
- events (no edge from emitter to receiver)

```
kernel: garbage, dbcore, input, verb_manager, tgui-transport   (no gameplay deps)

boot DAG (needs):
  db ─► time_track, persistence, death_stats, sqlite
  mapping ─► jobs ─► atoms ─► {holomaps, pois, assets, antag, radio, transfer, xenoarch, events, nightshift, pai}
  mapping ─► transcore, planets, research, supply, expedition
  native ─► gas_registry ─► atmos_pipes ─► atmos_devices;  native ─► {heat, power, gas_watch, gas_reactions, spacewind}
  atoms + pois + native ─► machines-capability ring
  shuttles ─► {flight, emergency_shuttle};  atoms ─► shuttles
  atoms ─► life ─► {life_present, life_vision, ai_brain}

uses (API, one direction each):
  flight ─► expedition (queries), flight ─► shuttles
  expedition ─► flight (destination_busy query)        ◄ query only; lint allows query-only back edges
  supply ─► contracts (commands);  contracts never calls supply (handles world_payment events)
  lighting ─► planets (sun_for_z query) ; planets publishes KEY_SUN(z) and never calls lighting
  round ─► (nothing);  jobs, antag, vote, emergency_shuttle, contracts ─► round (queries)
  profiler, time_track, statpanels ─► (nothing): metrics() only

events (emitter -> handlers, no dependency):
  native/*            -> gas_reactions, spacewind, power, gas_watch
  world_round_*       -> jobs, antag, emergency_shuttle, vote, supply, contracts, persistence
  world_mob_death     -> round (check_win), death_stats
  expedition/site_*   -> flight
  world_evac_returned -> round
```

| Metric | Before (b17) | After (target) | Gate |
|---|---|---|---|
| Schedulers | MC + OM (+ 34 world lanes, 22 pipelines, 216 periodic decls) | kernel (OM engine) | `subsystem_fire_lint` CORE = kernel five |
| Ways to repeat | 13 | 1 (cadence + `should_run`) | `kernel_timer_loop` |
| Rust drivers | 4 | 1 (`native`, phase N) | grep lint: `vg_world_tick\|vg_heat_tick\|vg_drain_events` only in `modules/native/` |
| Ordering vocabularies | 6 + 3 hand boots + 36 guards | 2 (`needs`; `after` within a pass) + the Rust law `after` | `system_boot_dag` test |
| Direct system→system edges | 63 (225 sites) | about 25 declared `uses` edges, all API | B2 + B4 |
| SCCs | 4 | 0 | B5 |
| External field accesses / writes | 1,657 / 242 | 0 / 0 | B1 + `VAR_PRIVATE` |
| Cross-folder system procs | 21 files | 0 | B3 |
| Hand-maintained registries | `world_services()`, the `pipeline_machines` roster, 44 `GLOBAL_DATUM_INIT` | 0 (`subtypesof` + capabilities) | - |

---

## 5. Performance, memory and testing

### 5.1 Tick cost

| Change | Expected effect | Measure with |
|---|---|---|
| The MC queue (`CheckQueue`/`RunQueue` over 11 SS) gives way to the kernel five | small saving per tick | `idle` |
| SSair, SSvg, lighting, tgui and ticker move from MC priorities into lane shares | **a scheduling change**: under load, lanes cap air/lighting where MC priority used to favour them | `atmos_large`, `major_events`, `explosion_dense`, `sm_soak` |
| One native drain instead of two, and heat moved into phase N | fewer FFI calls per 0.5 s; heat stepped once per tick with the elapsed time (it already uses elapsed, `heat.dm:367`) | `atmos_idle`, `atmos_large`, `radiation` |
| Events instead of direct calls | `OM_EMIT` allocates nothing without listeners; one proc call per handler | new `system_dispatch` scenario |
| `system(path)` lookup instead of the `SSx` global | one alist access; hot paths cache it in a local | `om_dispatch` |
| `should_run()` re-evaluation on every `changed()` for every system the entity is in | the main new cost; bounded by per-stage `wake_on` masks and per-type `systems()` tables | `life_sweep`, `idle_mobs` |
| Periodic declarations (216 defs, `sys_periodic_mask`) replaced by `should_run()` | removes the per-change mask dispatch in `om_dispatch_change`; adds one proc call per change | `life_sweep`, `om_dispatch` |
| World-lane trampolines (34 behaviour subclasses) become system rings | neutral | OM Profiler per system |

**Hard gates.** No scenario may regress more than 5% on median tick cost. `life_sweep` and
`atmos_large` may not regress more than 3%. Each stage's PR runs
`tools/build/build.sh bench --runs=3` then `bench-compare` against the previous stage.

### 5.2 Memory

- **Membership.** Each (system, member) pair costs one list slot (about 8 B) plus an alist index
  entry (about 24 B).
  - Example: 20k machines × 1.5 systems plus 1k mobs × 4 systems comes to roughly 34k entries,
    about 1.1 MB.
  - The capability-derived memberships replace several `REGISTRY_*` sets that hold the same atoms
    (machines, mobs), so the net is expected to be neutral or better.
  - `memory_breakdown` and `boot_memory` confirm it.
- **Per-type tables** (`systems()`, stage variants) cost per type, not per instance.
- **Deleted:**
  - 44 service singletons and their 34 behaviour trampolines;
  - 216 `sys_periodic_def` instances;
  - the `pipeline_machines` decl list;
  - per-SS `rolling_usage` buffers for 24 subsystems.
- **Watch this:** `alist` indexes on large member sets during boot. `boot_memory` peaks after
  `InitializeAtoms`.

### 5.3 Testing

**Unit tests** (new, `code/modules/unit_tests/`):

| Test | Checks |
|---|---|
| `system_boot_dag` | no cycle; every `needs` path is a system; the boot order is stable across runs |
| `system_membership` | capability init joins, destroy leaves, `add_capability`/`remove_capability` join and leave at runtime; no member survives qdel |
| `system_should_run` | a `changed()` wakes, `should_run()` FALSE parks, `PROCESS_KILL` parks, `rewake_in()` wakes on time (deterministic scheduler via `om_test_begin` / `scheduler_advance`) |
| `system_events_contract` | emitting an undeclared event runtimes in test builds; `events()` handlers are hooked once |
| `kernel_isolation` (K5) | a system whose step runtimes every call is parked after N faults and the other lanes keep running |
| `kernel_native_single_driver` | exactly one `vg_world_tick` per tick |
| existing `dq_atmos_tests`, `dq_expedition_tests`, `dq_contract_tests`, `dq_economy_tests`, `dx_core_tests`, `dq_world_lanes_tests` | ported, and must stay green at every stage |

**CI lints:**
- `system_boundary_lint.py` (B1–B7, baseline from the audit, shrink-only);
- `subsystem_fire_lint.py`, whose CORE list shrinks to the kernel five;
- `kernel_timer_loop` (a new rule in `scheduler_lints.py`);
- a ban on `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT`, `MACHINE_WAKE`, `om_task_periodic`, `boot_after`,
  `order_after` and `GLOB.*_service`, switched on by the commit that lands their replacement (the old
  `dx_old_forms` ratchet was removed as premature).

**Bench scenarios** (existing): `boot_profile`, `boot_memory`, `idle`, `idle_mobs`, `life_sweep`,
`om_dispatch`, `atmos_idle`, `atmos_large`, `major_events`, `explosion_dense`, `radiation`,
`generation`, `sm_soak`, `memory_breakdown`, `shared_cache`, `rustg_dispatch`.

**New scenarios:**
- `system_dispatch`: events, API calls and `changed()` fan-out at 10k members;
- `boot_order`: records the boot sequence and system init times, and diffs them per stage.

**Soak.** `tools/build/build.sh test-repeat --runs=5` on every stage that touches the kernel or
boot, and `test-baseline` for flakiness.

---

## 6. Migration order (green at every step)

**Preconditions:**
- `integrate/b17` has merged to master.
- The DX core (capabilities, refresh, `should_run`, TRACKED) has landed.

Each step is one branch, one compile, focused tests and the benches listed, then the full suite at
integration.

| # | Step | Keeps the build green because | Removes | Tests / benches |
|---|---|---|---|---|
| **1** | **Ratchets.** `system_boundary_lint.py` with the audit baselines (B1 1,657, B3 21 files, B5 4 SCCs); `metrics()` on SS and services; profiler, time_track and statpanels read only `metrics()` | lint baseline only; `metrics()` is additive | 17 observer edges | `idle`, stat panel smoke |
| **2** | **`/datum/system` base** in `code/controllers/kernel/system.dm`. `/datum/world_service/parent_type = /datum/system` and `/datum/cap_system/parent_type = /datum/system`. `system(path)` accessor. Registry by `subtypesof`; `world_services()` derived from it | parent_type keeps every existing service a valid subtype; `GLOB.x_service` still works | the hand list | `dq_world_lanes_tests`, `om_dispatch` |
| **3** | **Boot DAG over systems and subsystems** (mixed nodes). `boot_after` becomes `needs`; hand boots and comment dependencies become `needs` (split `pois` out of holomaps); `on_members_ready()` replaces `machine_first_wakes_flush()` | the same topo sorter; nodes include subsystems; order diffed against the current boot log | `boot_world_services_after`, `order_after`, 3 hand boots, most of the 36 guards | `system_boot_dag`, `boot_profile`, `boot_order` |
| **4** | **One periodic vocabulary.** `CADENCE_*` over the existing periodic pipelines. `DECLARE_PERIODIC_WHILE` (158) and `om_task_periodic` (74) become `periodic_cadence` + `should_run()`; `DECLARE_REPEAT` (58) becomes `periodic_interval`; `machine_step` becomes `periodic_step` with `MACHINE_WAKE` → `changed()`. Converted per domain folder in parallel lanes | `refresh_periodic()` already drives `om_task_periodic` from `should_run()`; old and new coexist per type until a folder is done | 216 declarations, `sys_periodic`, `MACHINE_WAKE`, `step_active` | `dx_core_tests`, `life_sweep`, `idle` |
| **5** | **World lanes become system cadences.** A service's `lane` behaviour becomes `periodic_cadence` + `should_run()` on the singleton (`on_demand`/`has_work` → `should_run`) | the ring engine is unchanged; only the trampoline goes | 34 `/datum/om/behaviour/world/*`, `demand()` | `dq_world_lanes_tests` (ported), per-service tests |
| **6** | **Native host.** One driver in phase N; one drain; heat out of SSair; `vg/on_*` handlers move to the owning systems as `events()`; SSvg splits into identity library + `vg_reconciler` | `run_gas_frames()` test hook preserved; Rust unchanged | 3 drivers, 2 drains, cross-folder SS procs | `dq_atmos_tests`, `atmos_idle`, `atmos_large`, `radiation`, `kernel_native_single_driver` |
| **7** | **Break the cycles**, one PR each: (a) round lifecycle (keys, events, API); (b) expedition/flight; (c) lighting/planets (`KEY_SUN`); (d) contracts/supply (ledger API, payment events) | each is local to 2–6 folders; the B5 baseline drops one SCC per PR | 4 SCCs | `dq_contract_tests`, `dq_economy_tests`, `dq_expedition_tests`, `major_events` |
| **8** | **Split hubs.** air becomes gas_registry, atmos_pipes, atmos_devices, spacewind, gas_reactions, heat facade. `machine_service` becomes power, atmos_devices, gas_watch. mobs becomes life, death_stats. Capability-derived machine membership (`powered`, `machine_work`) | per-hub PR; membership coexists with the decl roster until the pollers lint shows parity, then the roster goes | the `pipeline_machines` roster, `machine_service`, `mob_service`, `/datum/om/decl/living` | `life_sweep`, `idle_mobs`, `atmos_large`, `sm_soak` |
| **9** | **Firing subsystems become systems:** air (after 6 and 8), lighting (0 ticks → `CADENCE_TICK` on `LANE_PRESENTATION` with borrow), ticker (after 7a), profiler. NO_FIRE subsystems (18) become systems (the boundary is mechanical: `SUBSYSTEM_DEF(x)` → `/datum/system/x`, Initialize → `initialize()`) | the mixed-node DAG from step 3 lets a subsystem become a system one at a time | `SUBSYSTEM_DEF` for all but the kernel five | `boot_profile`, `major_events`, full suite |
| **10** | **Kernel host.** `kernel.dm` replaces the MC `Loop`/`RunQueue` for gameplay; SSbehaviours trampoline removed; failsafe watches the kernel heartbeat; `Recreate_kernel()` | the kernel five keep the tg subsystem shape; `run_pass()` untouched | about 800 lines of `master.dm` | `test-repeat --runs=5`, all benches, `kernel_isolation` |
| **11** | **Lints to zero:** B1 (field access), B2/B4 (API and `uses`), `GLOB.*_service` and `SSx` aliases deleted per system as converted | shrink-only ratchet; parallelisable per module (admin 27 systems, mob 23, …) | the remaining 1,657 accesses | full suite |

**Parallelism:**
- Steps 1 → 2 → 3 are sequential.
- Steps 4 and 5 can run in parallel.
- Steps 6, 7a–d and 8 can run in parallel after 3, each in disjoint folders with a single
  integrator per the batch-testing practice.
- Step 9 needs 6, 7a and 8.
- Step 10 needs 9.
- Step 11 is the long tail.

**Rough estimate:** 120–180 h. Steps 1–5 are about 45–60 h and remove most of the mechanism
duplication. Steps 6–8 carry the correctness risk.

---

## 7. Risks

1. **Budget semantics change** (steps 9 and 10).
   - Lighting (SS_TICKER, every tick) and air currently win on MC priority. In lanes they compete
     under fixed shares, so lighting on `LANE_PRESENTATION` at 15% could lag during an explosion.
   - Mitigations:
     - per-system `max_interval` borrow (the borrow pass exists);
     - allow a system to pin a lane share floor;
     - watch `explosion_dense` and `major_events` specifically.
   - Keep the MC fallback path until step 10's benches are within gates.
2. **The cost of `should_run()` re-evaluation.** DX re-evaluates on every change. Systems multiply
   the gates per entity. Keep `wake_on` masks on stages as an opt-in filter, keep `systems()` per
   type, and gate step 4 on `life_sweep`.
3. **Boot order surprises.** Folklore dependencies (holomaps→POIs, the auxmos lazy gas registry)
   will surface as runtimes when they become explicit.
   - The `boot_order` diff and `system_boot_dag` catch ordering.
   - Test builds assert that calling an uninitialized system's API is a runtime, so missing
     `needs` fail loudly instead of reading empty state.
4. **Loss of per-subsystem `Recover()`.** Systems live on; only the loop is recreated. The one
   real risk is a scheduler whose rings are corrupt. `Recreate_kernel()` rebuilds the rings from
   system membership, and the `kernel_isolation` test covers a faulting system.
5. **Tracing events is harder than tracing calls.**
   - `emits`/`events()` are static declarations, so the OM Profiler renders the graph and
     `system_boundary_lint --graph` prints it in CI.
   - The existing `om_world_trace` gives the runtime view.
   - Ban events used as RPC: an event with exactly one handler that returns a value is a lint
     warning, and should be an API command.
6. **Over-declaration drift.** `uses` and `emits` go stale if nothing checks them. They are checked:
   B4 plus test-build asserts on emit. `needs` is checked by the boot order itself.
7. **DreamChecker private and protected only work at lint time.** A runtime `vars[]` access
   bypasses them. The `dx_string_names` lint already bans string var names in gameplay code.
8. **tg kernel code.** Garbage, input, tgui, dbcore and the failsafe stay in the tg subsystem shape
   so fixes can still be ported. Do not "systemise" them.
9. **Merge pressure.** Steps 4 and 11 touch hundreds of files. Convert per folder, with one
   integrator, and keep the ratchet shrink-only so a half-converted folder is still green.
10. **Scope interaction with DX.** This design assumes DX step 1 (core plus the standard
    capability library) has landed. Running steps 4 and 8 before the capability library exists
    would mean inventing capabilities twice. Sequence it after DX step 1, in parallel with DX
    domain migrations (DX step 2), and do it folder by folder in the same PRs where possible.

---

## Implementation notes (branch rewrite/kernel)

What exists in the tree, so the sections above are not read as all-future.

- **Systems** (`code/controllers/kernel/system.dm`): `/datum/system` with `needs`, `emits`, `members`,
  `periodic_runlevels`, `member_cadence`, `latency_class`; `system(path)` and the registry (`system_table()`).
  `/datum/world_service` and `/datum/cap_system` both have it as `parent_type`. `world_services()` is still the
  hand roster (its order is the lane-attach and shutdown order); a unit test keeps it in step with the registry.
- **Step protocol**: `periodic_step(dt)` returns `STEP_DONE` (stay), `STEP_YIELD` (resume next tick) or
  `STEP_PARK` / `PROCESS_KILL` (leave until `wake_periodic()`). `om/periodic.dm` reads the result; a pure system
  is put on its cadence by `kernel_start_periodic()` after boot, and `wake_periodic()` / `park_periodic()` restart
  and stop it. `member_should_run` / `member_step` are called by `/datum/system_member_driver` on `member_cadence`.
- **Cadences** are the periodic pipelines (`CADENCE_FAST/SECOND/SLOW/MINUTE`); `periodic_interval` overrides.
- **Boot** (`kernel/boot.dm`, `master.dm`): systems and subsystems are nodes of one DAG; a subsystem's
  `dependencies` may name systems (SSatoms names transcore and planets); `on_members_ready()` runs once after
  the DAG and replaces the machine first-wakes special case.
- **Latency classes** (`kernel/latency.dm`): L0 input (clicks and verbs; never shed; the click queue holds a
  click for the next tick once tick usage passes `VERB_HIGH_PRIORITY_QUEUE_THRESHOLD`, drained first by
  `SSinput`, bounded at `KERNEL_CLICK_QUEUE_MAX`), L1 deadline (`LANE_URGENT`), L2 defer (`LANE_SIMULATION`,
  `LANE_DERIVED`), L3 shed (`LANE_PRESENTATION`, `LANE_BACKGROUND`). `KERNEL_SHED_STREAK` consecutive ticks over
  100% start shedding L3; each L3 lane or system still gets one pass per `KERNEL_SHED_FLOOR`; `KERNEL_SHED_RECOVER`
  calm ticks end it. Input latency is a per-tick histogram read for p50/p95/p99 (`metrics()`).
  Shedding is off in unit-test builds. Not done: `MouseDrop` and key input are not queued; the K-phase cap only
  counts over-cap use.
- **await()** (`kernel/waiter.dm`): waiters are resolved by `waiter_resolve()` / `waiter_cancel()` or a timeout
  checked once per tick; the awaiting proc still parks on a one-tick sleep (DM cannot resume a proc from outside).
  `/datum/om/io/rustg_job` is the I/O kind for a caller-started iconforge job. The 68 legacy `stoplag()` / modal
  wait sites are not converted.
- **Lint**: `tools/ci/system_boundary_lint.py` (B1-B7, shrink-only baseline).

## Implementation notes (branch rewrite/f-kernel)

Built on top of the notes above.

- **kernel_tick** (`code/controllers/kernel/kernel.dm`): `kernel().tick(limit, init_stage)` is called once per tick by
  the kernel's own loop (`loop.dm`; the MC `Loop` and its queue are gone, see scheduling_and_kernel.md section 7).
  Phases: **K** hosted `SSinput` / `SSverb_manager` / tgui / dbcore / profiler (`SS_KERNEL_HOSTED`; use over
  `KERNEL_INPUT_CAP` is counted), **N** `native_frame(elapsed, budget)`, **U** urgent slice, **D** deadline wheel then
  deadline-phase work items, **P** borrow pass then each lane (scheduler share, then that lane's work items), **R**
  leftovers, **G** hosted `SSgarbage` with a floor (`KERNEL_GARBAGE_FLOOR` per `KERNEL_GARBAGE_FLOOR_PERIOD`). Each
  phase is guarded: a runtime is logged, counted (`phase_faults`) and the tick goes on. The scheduler's `run_pass()`
  is now `pass_begin / pass_deadlines / pass_borrow / pass_lanes / pass_leftovers / pass_end`; run_pass() still runs
  them all for the test harness, and the kernel runs the same pieces between its phases (`native_hosted` moves
  `world_step()` to phase N).
- **SSbehaviours dissolved**: `SS_NO_FIRE`; its pass (the scheduler's pieces are kernel work items, `controllers/kernel/sched_items.dm`), pipeline audit (SSbehaviours' `audit_step` work item), `bench_ms`, `cost` and `last_done`
  are fed by the kernel. It still boots the registry, scheduler and world lanes.
- **native_frame** (`kernel/native.dm`) is a stub for the Rust owner: it steps the OM world wheel. `vg_world_tick`,
  `vg_entity_tick_all`, `vg_drain_events` (SSvg) and the gas phases + `vg_heat_tick` (SSair) still run where they did.
- **Work items** (`work_item.dm`, `work_engine.dm`): see the migration guide A12 for the API. Ordering is per phase
  with `after` edges resolved to items (owner type = all its items, string = item key) and validated by
  `graph_validate()`, the same call the boot DAG uses. Cost accounting per item and per owner type is in
  `kernel().metrics()` and each system's `metrics()["reactions"]`. A memberless item runs on the owner
  (`system(owner_type)`); an item with `members =` sweeps `members_of(key)` with a resumable cursor.
  A capability type named in `members` joins holders in `caps_init` only if it was registered before they initialized.
- **Urgent requests** (`urgent.dm`), **membership relations** (`membership.dm`), **stage adapters** (`stage_work_item`)
  and **clocks as sources** (`work_clock_now`, entity clocks via `om_clock_now`): as in the migration guide.
- **Rosters removed**: `system.members`/`member_index` (now `member_list()`), `cap_system/roles.by_role`
  (`cap_system_members()`), the `world_services()` hand list (derived from the registry, so its order is registration
  order instead of the old hand order).
- **Subsystem conversions** (was deferred here, done on rewrite/g3-kernel): air, vg (into native), lighting, ticker,
  shuttles, job, contracts, persistence, holomaps, media_tracks, nerdle, robot_sprites, speech_controller, mapping,
  access, admin_verbs, internal_wiki are `SYSTEM_DEF` systems; `SSx` names the instance. The failsafe watches
  `kernel().last_tick` and `Recreate_kernel()` exists. See scheduling_and_kernel.md section 7.
