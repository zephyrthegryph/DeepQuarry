# Which time mechanism?

One page. Every mechanism below runs on the object-model scheduler (SSbehaviours) or is a
plain time comparison; there is no SStimer, no `spawn()`, no gameplay `sleep()`, no
`process()`. Details: [object_model_core.md](object_model_core.md) §4.5 to §4.12, §16.

## Pick by question

| I want to... | Use | Owned by / cancelled when | Not |
|---|---|---|---|
| Call a proc once, later | `om_after(E, delay, PROC_REF(x), args...)` (returns an id) | E; dropped if E or any datum arg is deleted; paused with E's clock | `addtimer`, `spawn`, `sleep` |
| ...only if not already pending | `om_after_unique(E, delay, proc, args...)` | same | `TIMER_UNIQUE` |
| ...restarting it if pending | `om_after_replace(E, delay, proc, args...)` | same | `TIMER_OVERRIDE` |
| Cancel / query that call | `om_cancel_timer(E, id)`, `om_timer_left(E, id)`, `om_cancel_calls(E, proc)` | - | `deltimer`, `timeleft` |
| Repeat something | a proc that works and calls `om_after_replace()` again; or a cadence (below) | - | `TIMER_LOOP` |
| Real-time (not game-time) delay | `om_after_realtime(delay, proc, args...)` on the global owner | global owner | `TIMER_CLIENT_TIME` |
| Delete something later | `expire(d)` on a movable (`expire(null)` disarms); `om_qdel_after(D, d)` otherwise | the object | `QDEL_IN` |
| Wake one behaviour hook after a delay | `om_deadline(E, delay, B, sub)` -> `B.on_deadline(E)` / `on_keyed_deadline(E, sub)`; `om_cancel_after`, `om_deadline_pending` | E + behaviour; one per (E, B, sub), re-arming replaces | a `world.time` compare in periodic work |
| Rate-limit an action ("not more than once per N") | `COOLDOWN_DECLARE(x)`, `COOLDOWN_START(src, x, d)`, `COOLDOWN_FINISHED(src, x)` | nothing to cancel: it is a stored time compared on read | `TIMER_COOLDOWN_*`, hand-kept timestamps |
| Run a behaviour at a steady rate | behaviour `every = d` (+ `max_interval`, `max_dt`, `step_interval`/`max_catchup` for fixed steps) -> `tick(E, dt)` | ring membership: park/suspend/requires/relevance take it off | `process()`, `START_PROCESSING` |
| Run periodic per-object work that should stop when idle | a periodic lane: `PERIODIC_START(E, PERIODIC_SLOW/FAST/...)`, parks when its stage idles | the entity | `process()` |
| A pipeline stage that is idle but still drifts | the stage's `rewake_delay(E)` (a keyed deadline) | entity + stage | a cadence that polls |
| A stage that runs no more than every N | stage/behaviour `min_interval` (wakes coalesce into one deadline) | - | throttling by hand |
| Time that runs slower/faster per object (stasis, freezers, bio time) | a clock domain: behaviour `clock = CLOCK_X`; `om_clock_now(E, CLOCK_X)`, `om_clock_rate_of()`; slow things by holding `EFFECT_CLOCK_X_INHIBIT` / `_MULT` | contributions | `world.time` in biological code |
| Take time over an action with a progress bar | a task: `om_task_start(/datum/om/task/timed/x, actor, target, var = value...)`; steps return `STEP_NEXT`, `STEP_REPEAT(d)`, `STEP_DONE`, `STEP_FAIL(r)` | actor + target; cancelled on move, deletion, failed `requires`, `interrupted_by` | `do_after` |
| Time, then ask, then act | a flow: `om_flow_start(/datum/om/flow/x, actor, target, ...)` with `wait(d, next)` and `om_ask()` steps | the task or prompt it waits on | procs chained by hand |
| Long loop that must not hog a tick | `om_lane_work(E, slice_proc, cursor, on_done)`: slices resumed by cursor within the budget | E | `stoplag()`, `CHECK_TICK` sleeps |
| World-level periodic work (no entity) | a `/datum/world_service` with a `lane` behaviour on the global owner; `on_demand` + `demand()` parks it while idle | the service | a subsystem `fire()` |
| Wake at an exact tick, on a Rust-owned value, a DM key or a rate crossing | a world watch: `om_world_at`, `om_world_on_change`, `om_world_when`, `om_world_on_key`, `om_world_on_rate` (delivered on the watch's `lane`) | owner keeps the watch, `qdel(watch)` cancels | polling gas/heat each tick |
| React when a declared field changes | `OM_FIELD` + behaviour `wake_on` / stage `reads` -> `on_wake(E, changes)` | - | a timer that re-checks |
| Wait on SQL / HTTP | `om_io(E, /datum/om/io/sql or http, args..., on_done)` | E; callback dropped if E is gone | `set waitfor`, `INVOKE_ASYNC`, blocking `Execute()` |

## Lanes (where scheduled work runs)

Each scheduler pass: deadlines first (20% of the budget guaranteed), then the borrow pass for
rings near `max_interval`, then each lane with its guaranteed share, then leftovers.

| Lane | Share | Put here |
|---|---|---|
| `LANE_URGENT` | 30% | player-visible correctness that can't slip (world watches on this lane drain in full) |
| `LANE_SIMULATION` | 30% | default: game simulation, Life, machines |
| `LANE_DERIVED` | 15% | derived values, services, recomputes |
| `LANE_PRESENTATION` | 15% | HUD, icons, UI pushes |
| `LANE_BACKGROUND` | 10% | slow bookkeeping, audits |

Cost per behaviour, lane, pipeline stage and world service: admin verb **OM Profiler**
(Debug > Investigate).

## Rules of thumb

- A time you only compare on read is a `COOLDOWN_*`. Anything that must *do* something at a
  time is `om_after` / `om_deadline`.
- Work that repeats while something is true is a cadence or periodic lane that parks when it
  isn't; never a timer that re-arms forever "just in case".
- Anything owned by an entity is torn down with it; don't cancel in a destroy hook what the
  scheduler already drops.
