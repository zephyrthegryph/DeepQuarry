# Scheduling, systems and the kernel

Status: **[in progress]** on `rewrite/f-kernel` (owner W5), on top of `rewrite/kernel`; the host loop, the system
conversions and the first stage moves landed on `rewrite/g3-kernel` (section 7). The detailed
design and its measurements are in [kernel.md](kernel.md); this chapter is the foundation-level
contract and overrides kernel.md where they differ (see section 6). Overview:
[foundation.md](foundation.md).

## 1. The host loop

`kernel_tick()` is the host loop for gameplay, replacing the MC `Loop` for gameplay work. One pass
per tick, in fixed phases:

| Phase | Runs | Budget rule |
|---|---|---|
| **K** | Host kernel subsystems: input, verb_manager, tgui transport, dbcore, sqlite, assets, atoms, overlays, profiler | first; capped for latency |
| **N** | Native: the single `vg_frame(elapsed, budget)` and delivery of its outbox ([rust.md](rust.md)) | one call per tick |
| **U** | Urgent requests: `request_urgent` work with deadlines | reserved slice |
| **D** | Deadlines: `after()` timers, deadline wakes, timed reverts | protected share |
| **P** | Phased work items: `every()`/`on_cross` items grouped by `phase=` and ordered by `after=` edges, run by lane share | remaining budget |
| **R** | Leftovers, in lane order | whatever is left |
| **G** | Garbage (kernel subsystem) | leftover with a per-second floor |

`SSbehaviours` dissolves into the kernel; the OM scheduler is the engine of phases D, P and R. Host
services (garbage, input, verb_manager, tgui transport, dbcore, sqlite, assets, early_assets,
atoms, overlays, profiler) stay kernel subsystems. Boot/shutdown and direct commands are system
behaviour but are not scheduled work. BYOND callbacks (`Move`, `Login`, `Topic`, verbs) stay thin
adapters to operations, setters, notices or work requests.

## 2. Systems and work

A `/datum/system` owns domain state and a public API (`api.dm`). It contributes **work items**,
which are reactions ([reactions.md](reactions.md)):

```text
every(interval, handler, when=, members=, phase=, after=, budget=, lane=)
on_cross(read, bands, handler, urgent=)
on_notice(type, handler)
```

The reaction constructors produce `/datum/work_item/reaction` items (`code/datums/reactions/work.dm`;
how each kind is registered, enrolled and called is in [reactions.md](reactions.md) section 1a). On a
work item `while` is a reserved word in DM, so the constructor argument is `when` and the field is
`run_when`; `runs_while(...)` (the `should_run` reads sugar) is a different thing. An `on_notice` or
non-urgent `on_cross` item is an *event item* (`event = TRUE`): it is registered so `metrics()` accounts
its cost, and the kernel never schedules it.

A work item has membership (`members = <capability type>` runs it per member), a trigger, its
observed inputs, a `phase`, ordering edges (`after =`), and a `budget`. A **pipeline** is only a
named ordered group of work items: stages become work items with after-edges inside a phase.
A stage's `should_run` with declared reads replaces `idle`/`wake_on`/`rewake_delay`; adapters keep
the 294 existing stages running without migrating them.

**Two graphs, one validator.** Boot dependencies say which owner initialises first; runtime
`after` edges order work inside a phase. Both are checked by one graph validator; a missing target
or a cycle fails validation.

**Steps.** Work yields with the `STEP_*` protocol (`STEP_YIELD` resumes later without sleeping
inside a step). Clocks are sources: world, biological (stasis-aware) and machine clocks may advance
differently. Each work item's cost is accounted in `metrics()`.

## 3. Membership is relations

System membership is `MEMBER` relations created from capabilities and `join(system, E, source)`
([state_and_relations.md](state_and_relations.md)). Two features enrolling one entity give a source
count; membership ends when the last contributor leaves. The three hand-kept rosters
(`system.members`, the former cap_system roles and the `world_services()` list) are deleted behind
wrappers.

Gameplay subsystems become `/datum/system` where feasible without behaviour change: air, native
(vg), lighting, ticker, shuttles, job, contracts, persistence, holomaps, media_tracks, nerdle,
robot_sprites, speech_controller, mapping, access, admin_verbs, internal_wiki. The ones that cannot
move without behaviour change are listed as deferred by the kernel branch's report.

## 4. Urgent requests

```text
request_urgent(member, work, deadline)
```

Wake, urgent request and direct execution are different ([reactions.md](reactions.md) section 5).
An urgent request:
- gets a **reserved budget slice** (phase U) instead of relying on lane priority, which is not a
  latency guarantee;
- is **deduplicated** per member and work;
- carries elapsed time and an **execution token**, so the later cadence run does not double-apply
  the same interval;
- records a **breach metric** when the deadline is missed under load.

Typical use: a native air source publishes a dangerous change (`on_cross(..., urgent = TRUE)`); the
occupant's respiration work runs within a stated tick deadline even if the mob was hibernating.
The latency guarantee starts when the native source publishes; the native step's own delay is
measured separately, and a short safety resample remains for critical occupied spaces.

## 5. Sleeping and waiting

`ask_*` and `await_*` are the only suspension points in gameplay code. Raw `sleep`, `spawn`,
`stoplag` and `UNTIL` are lint errors outside the ask layer and the kernel.

## 6. Where this overrides older docs

| Older text | Now |
|---|---|
| [kernel.md](kernel.md): phases K, N, D, B, L, R, G with lanes | K, N, U, D, P, R, G; borrow (B) and lanes (L) fold into P by `phase=` and lane share |
| kernel.md: work units are cadence, deadline, wake | work items are `every`/`on_cross`/`on_notice` reactions; timers are `TIMER` relations |
| kernel.md: `member_should_run`/`member_step` | `every(..., members = <capability>)` |
| kernel.md: rosters and `world_services()` | `MEMBER` relations |
| `archive/systems.md`, `archive/life_on_om.md` | this chapter; Life detail stays in `doc/mob_life_architecture.md` |

## 7. Where it stands (branch rewrite/g3-kernel)

**The kernel is the host loop.** `kernel().loop()` (`code/controllers/kernel/loop.dm`) replaced the MC `Loop`; there is
no subsystem queue (`CheckQueue`, `RunQueue`, `SoftReset`, `enqueue()` and the queue links are deleted). One loop
generation runs at a time (`loop_gen`); `Recreate_kernel()` supersedes it and starts a fresh one without touching the
systems or subsystems, rate limited like `Recreate_MC()` was. The failsafe watches `kernel().last_tick` and the kernel's
stack-end detector, and its emergency path calls `Recreate_kernel()`; "Restart Controller" restarts the kernel;
"Debug Controller" lists the kernel and the systems. `Master` is a shim: it keeps boot (`Initialize`, the init DAG over
subsystems and systems), the run level, and the values code reads from it (`iteration`, `last_run`, `sleep_delta`,
`tickdrift`, `current_ticklimit`, `current_runlevel`, `processing`, `init_stage_completed`, ...), which the kernel loop
writes with the meaning they had.

**Host services** are the subsystems that still exist, all `SS_KERNEL_HOSTED`: phase K runs input, verb_manager, the tgui
transport, dbcore and the profiler (sqlite, assets, early_assets, atoms, overlays and behaviours have no fire); phase G
runs garbage (`host_phase`). A host on a longer wait than a tick gets at most `KERNEL_HOST_SLICE` percent of a tick, a
ticker the whole phase. A runtime in a host is caught and counted like a phase fault.

**Systems.** `SYSTEM_DEF(x)` declares `/datum/system/x` and keeps `SSx` as the name of its instance (the kernel creates
every pure system in `Master.New`, before the globals), so the 7-433 call sites per system did not move. Converted:
access, admin_verbs, air, contracts, holomaps, internal_wiki, job, lighting, mapping, media_tracks, nerdle, persistence,
robot_sprites, shuttles, ticker, speech_controller, and vg, which dissolved into `/datum/system/native` (`SSvg` is the
native system; the entity table is `code/datums/native/entities.dm`). `Initialize()` became `initialize()`,
`dependencies` became `needs` (the boot DAG orders both kinds of node; `init_stage` keeps the stage the subsystem had),
`Shutdown()` became `on_shutdown()`, `Recover()` is gone (nothing recreates a system). A system with a `fire()` body
(air, lighting, ticker) declares `every(wait, PROC_REF(fire_step), when = PROC_REF(fire_ready), lane = ...)` in
`reactions()`: `fire_step()` calls the old body with `resumed`, turns `MC_TICK_CHECK` pauses into `STEP_YIELD`, and keeps
`times_fired`/`fire_cost`/`ticks`. Air and the ticker run on the simulation lane, lighting on the presentation lane (so
it is shed under overload, as a ticker at L3 would be). The speech controller is a phase K work item over a
`/datum/verb_lane` (the queue SSverb_manager shares).

**Periodic work is kernel work.** The twelve `PERIODIC_*` / `CADENCE_*` pipelines are `/datum/cadence` definitions, each
with one sweep item (`/datum/work_item/cadence`, phase P, the cadence's lane, run levels and clock); `om_task_periodic()`
joins the cadence's membership and `om_task_periodic_stop()` / `PROCESS_KILL` leaves it. A sweep looks again at a slot
whose member left mid-step, so the member swapped into it is not skipped. A hotspot's burn is an `every()` on
`/obj/effect/hotspot`.

**Spread sweeps.** A cadence slower than the tick sets `work_item.spread`: its sweep is spread across the interval
(`run_item_spread()`, the old ring's phase property). Each pass runs the members due by the end of that tick (the share of
the interval elapsed since the sweep began), so every member keeps its phase and a large set costs a slice per tick rather
than a spike once per interval. A sweep that fell behind catches up by at most `KERNEL_SPREAD_CATCHUP` passes' share per
pass; the next sweep begins one interval after the last began, or at once if it ran late. Cost is counted once per sweep.

**Stages.** The 13 periodic stages and the 2 hotspot stages moved. The 228 life stage definitions and 23 machine stage
definitions (plus the test and bench fixtures) still run on the object-model engine: a frame is per entity (shared
facts, `F.abort()`, plans per entity type and variant, idle bits, parking, relevance, the missed-wake audit,
`om_stage_run_now()`), which a stage-major work item does not reproduce. `kernel_stage_adapter_graph` adapts every one of
them with `stage_work_item()` and validates their after-edges in one graph, which is the gate before a pipeline moves.
Stages will move when a pipeline can keep its frame (facts, abort, parking) on the kernel side; until then
`code/datums/om/pipeline.dm` stays.
