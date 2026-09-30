# Scheduling, systems and the kernel

Status: **[in progress]** on `rewrite/f-kernel` (owner W5), on top of `rewrite/kernel`. The detailed
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
