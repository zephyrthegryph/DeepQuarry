# SSreactor (track S)

SSreactor is the single scheduler on the DM side. It delivers wakes from Rust watches, fires DM timers, runs the few processes that really are continuous, and dispatches changes to DM-owned state.

It replaces nine separate mechanisms:
- SSmachines' reactive keys and gas subscriptions;
- SSai's chunk hibernation;
- SSobj;
- SSprocessing;
- most SSfastprocess users;
- SSbellies;
- SSburning;
- SSmaterial_services;
- the heavy SStimer users.

DCS signals stay for synchronous behaviour hooks (§8).

## 1. API

```dm
/// Called when a subscription fires. `reason` is REACT_REASON_* class bits OR-ed with channel
/// bits (a change watch) or the key's mask (a key); `source` is the first reason's source (the
/// cell, the timer's token, the key id with `source_kind` its kind, or the rate model).
/datum/proc/on_react(reason, source, source_kind)
/// A continuous-lane run: scale by `seconds`, the real time since the last run.
/datum/proc/react_every(seconds, token)

REACT_ON(src, handle, CH_BIT(CH_GAS_PRESSURE)|CH_BIT(CH_GAS_TEMPERATURE)) // channel change on a Rust entity
REACT_WHEN(src, COND_ABOVE(handle, CH_GAS_PRESSURE, 5000))  // a condition watch (COND_ABOVE/BELOW/BAND/DIFFERENCE)
REACT_AT(src, world.time + 10 SECONDS)                      // one-shot timer at tick precision
REACT_EVERY(src, 2 SECONDS, "why this is continuous")      // declared continuous work
REACT_PUBLISH(kind, id, mask)                                // DM-owned state changed
REACT_ON_KEY(src, kind, id, mask)                            // subscribe to DM-owned state
REACT_RATE(src, model, REACT_CMP_ABOVE, level)              // a rate model crosses a level
REACT_CANCEL(src, token)                                     // drop one subscription, timer or declaration
REACT_CLEAR(src)                                             // drop everything; called by the base Destroy()
```

As built (S1): `code/__defines/reactor.dm`, `code/controllers/subsystems/reactor.dm`, and the
binds in `verdigris/ffi/src/reactor.rs`.
- The handler is `on_react`, not `react`: `/datum/gas_mixture` and `/datum/gas_reaction` already
  own a `react()` with another meaning.
- Every subscribing macro returns a **token** for `REACT_CANCEL`. Rust tokens are
  `index * 16 + (generation & 15)`, so a stale token never cancels a newer subscription.
  Continuous declarations have negative tokens and live in DM.
- A **handle** is `REACT_HANDLE(domain, cell)`: a domain (< 16) and a cell (< 2^20) in one exact
  number. Until the real domains move onto `vg-core` (M1b for gas), the only watched domain is
  the **probe** (`REACT_DOMAIN_PROBE`): DM-written pressure/temperature cells that exercise the
  whole watch path (registration checks, frame evaluation, stale filtering, lanes) from DM tests.
  A real domain adds its `WatchPort` to the host in `reactor.rs`.
- A **key** is a kind (`REACT_KEY_*`, < 256) and an id (< 2^24, normally the owner's
  `REACT_ID`), passed as two numbers so both stay exact.
- Lanes: `SSreactor.on_key(D, kind, id, mask, REACT_LANE_URGENT)` and the other procs take a lane;
  the macros use the normal lane.
- Per tick SSreactor makes **one** bind call, `vg_react_step(tick, budget)`: it fires timers and
  rate crossings, dispatches key publications, evaluates the domain watches and returns the
  tick's wakes as one flat list, `REACT_WAKE_STRIDE` numbers per wake. Dispatch pauses on
  `MC_TICK_CHECK` and resumes on the same list.
- Registry ids freed by `REACT_CLEAR` are reused only from the next tick, so a wake already
  returned for an id never reaches the datum that inherits it.

- **One registry index per subscriber.** A subscriber holds only that index, a single number. The subscriptions themselves live in Rust ([rust_core.md §6-7](rust_core.md#6-channels-and-watches)), so datums carry no lists.
- **Idempotent `react()`.** The same subscriber is woken at most once per lane per tick, with its reasons merged. Handlers must cope with spurious and merged wakes: read the current state, never count wakes.
- **Handlers never sleep.** Long work goes to a job or an async callback.
- **Cleanup.** The base `/datum/Destroy()` calls `REACT_CLEAR`.

## 2. The continuous lane

A few things really do change every tick while they are active: the supermatter, projectiles, and some mob life systems until the body rewrite's hibernation lands.
- **Declared, never defaulted.** Continuous work is registered with `REACT_EVERY` and a one-line justification. The declaration shows up in the profiler.
- **Scaled by elapsed seconds** (AGENTS.md §3e), so sleeping and waking never change rates.
- **Self-cancelling.** It stops itself with `REACT_CANCEL` once its sleep condition holds.

As built: the continuous lane lives in DM (`SSreactor.continuous`), because it runs DM code every
period anyway and few declarations exist. Each runs `react_every(seconds, token)` after the tick's
wakes, where `seconds` is the real time since its last run; its cost is recorded by type.

## 3. Timers

- The timer wheel lives on the main side, in Rust. Inserting and cancelling take constant time, and no datum is created per timer.
- Timers fire at tick precision.
- `REACT_AT` replaces deadline polling: airlock `close_door_at`, `main_power_lost_until` and `electrified_until`, camera EMP recovery, cooldowns.
- SStimer stays for general callbacks until S4 moves the heavy users. Its per-insert debug list is fixed first (fixes.md Q10).

As built: the wheel is R5's `TimerWheel` inside the main-side `Reactor`, reached through
`vg_react_at`/`vg_react_cancel`. It runs in DM ticks (`SSreactor.tick_of(time)` is the first tick
at or after `time`); a past deadline fires at the next step. Keeping it in Rust costs no datum,
list entry or DM loop per timer, and timers share the lanes with watch and key wakes, so a timer
and a watch landing in one tick merge into one `on_react()`. A DM wheel would need a per-timer
record and a bucket scan per tick, which is what SStimer already pays for.

## 4. DM-owned keys

State that only DM changes (door modes, area alarms, turret targets) is published with `REACT_PUBLISH`.
- Publications are merged per tick and dispatched on the main thread.
- Keys are numeric, built from registry IDs rather than strings, so publishing costs no string building. Today every `use_power_*` call builds an `area_power:[REF]` string.
- A key with no subscribers is never stored.

## 5. Rate models for DM-owned quantities

Quantities that change at a known rate use the main-side rate models ([rust_core.md §7](rust_core.md#7-the-main-side-reactor)): item rot, consumable fuel, cooldown meters, digestion progress. DM reads the current value, and thresholds become timers at the exact crossing time.

## 6. Mob life systems (with the body rewrite)

`doc/mob_life_architecture.md` defines life systems with wake bits, and plans for them to use `subscribe_gas_dependency` and `publish_reactive_dependency`. Under this rewrite:
- A life system's `attach()` registers its dependencies with `REACT_ON`, `REACT_WHEN` and `REACT_AT`.
- The mob's `react()` sets the matching `life_awake` bits and rejoins SSmobs if it was hibernating.
- Comfort bands become `Band` watches on the mob's body heat node and breathing mixture, instead of re-subscribing on every `Moved()`.
- The mob-life missed-wake tests and the hibernation audit apply unchanged.

Agree this interface with the body rewrite before S2 migrates any caller.

**The hook (agreed with the body rewrite).** The body rewrite's only wake is
`/mob/living/proc/life_wake(bits = LIFE_SYS_ALL, reason, partial = FALSE)` and its only hibernate
is `life_hibernate(reason)`; its lint forbids writing `life_hibernating`, `life_awake` or
`hibernating_mobs` outside `scheduler.dm`. The reactor reaches mob Life through exactly one
proc, `/mob/living/proc/reactor_wake(bits, what)` (in `code/controllers/subsystems/reactor.dm`),
which becomes `life_wake(bits, "reactor:[what]")` after the body rewrite's wave-4 merge (until
then it calls the scheduler's current `wake(bits)`). The flow:
1. A life system's `attach()` subscribes the mob:
   `REACT_WHEN(mob, COND_BAND(turf_gas, CH_GAS_PRESSURE, comfort_levels))`, the same for
   temperature, and `REACT_AT` for its timers.
2. The mob's `on_react(reason, source)` maps the reason to its systems' wake bits (gas channels
   to the `LIFE_WAKE_BODY` systems, timers to the system that set them) and calls
   `reactor_wake(bits, "gas")` once, with the bits merged.
3. `life_hibernate()` never talks to the reactor: the subscriptions stay while the mob sleeps,
   which is the point.

The first user is the body rewrite's known gap: atmos changes around a standing mob are not an
event yet (a 15 s timer covers it). A pressure/temperature `Band` watch on the mob's turf
mixture replaces that timer once gas is a watched domain (M1b). Moving to another mixture
re-registers the watch (`REACT_CANCEL` the old token, `REACT_WHEN` on the new one) instead of
re-subscribing on every `Moved()`.

## 7. Missed-wake safety and metrics

- **Wake tests.** Every subscriber type gets a wake test: change its input and check it woke; hold the input steady and check it stays asleep. This extends the pattern the body rewrite uses.
- **Audit.** A debug audit samples sleeping subscribers and logs any whose sleep condition no longer holds. This replaces `audit_reactive_sleepers`, which has no callers today.
- **Metrics.**
  - Wakes by type and reason class (bounded).
  - Continuous-lane cost by type.
  - Timer counts.
  - Dispatch time.

  The profiler and the benchmarks read them. Today's `machine_wake_reason_counts`, which grows all round (B4), is replaced.

As built:
- `SSreactor.performance_diagnostics()` gives wakes by type and reason class (`changed`,
  `condition`, `timer`, `key`, `rate`, `every`; at most `max_metric_types` types, the rest
  under `other`), continuous-lane declarations with their justification and cost, dispatch time,
  and the Rust counters (`vg_react_stats`). The profiler's `PERF_PROFILE` record has it under
  `subsystems.reactor`; each benchmark window records it as `<window>_reactor`, plus the metric
  `<window>_reactor_wakes`. The Rust counters are also in `verdigris_metrics()` as `reactor.*`.
- `SSreactor.audit(sample)` asks sampled subscribers `react_sleep_violation()` (null while the
  sleep condition holds). It runs every `audit_interval` only in test and dev builds (UNIT_TESTS/TESTING,
  where a finding is a runtime that fails the run) or, on servers, with the `reactor_audit` config
  flag (off by default; an admin can enable it for one round). Findings log as `REACTOR_AUDIT`.
- `react_wake_test(D, change)` (unit tests) is the wake test for any subscriber type: held
  steady it must not wake, after `change` it must.

## 8. Signals or the reactor?

| Use a DCS signal when… | Use the reactor when… |
|---|---|
| The listener must run now, in the same call stack (to cancel an attack, modify a value in flight or react to an equip) | The work can wait until the next dispatch, and many changes should merge into one wake |
| The relationship is behavioural (an element reacting to its host being examined) | The dependency is on simulation state (gas, heat, power, networks) or on time |
| There are few listeners per sender | Thousands of objects depend on shared state (a pipe network, an area's power) |

## 9. Migration

| Replaced | By | Item |
|---|---|---|
| `reactive_revisions`, `reactive_subscribers`, `reactive_sleepers`, `hibernate_reactive_machine`, `publish_reactive_dependency`, `wake_reactive_machine` (`machines.dm:86-94, 767-846`) | Watches and DM-owned keys | S2 |
| `sleeping_gas_devices`, `gas_mixture_subscribers` and friends (four lists per watched mixture), `wake_dirty_gas_subscribers`, `wake_gas_subscriber`'s 20-branch `istype` chain, the `hibernate_*` helpers (`machines.dm:852-1141`) | `REACT_ON` on gas handles. Devices, air alarms and firedoors move to Rust in M2. | S2, M2 |
| SSai `chunk_subscribers`, `sleeping_brains`, `hibernate_calm_brain`, `wake_brain` | Numeric chunk keys | S2 |
| Airlock, camera and light deadline polling; status display `update()` every tick | `REACT_AT`, and pushed updates | S3 |
| Looping sounds for nobody (62 s per 3 h) | Loop only while a listener's chunk key is subscribed | S3 |
| `wake_all_automatic_shutoff_valves()` | Wakes per network | S3 |
| `area/power_change()` scanning the area's contents | The area channel event from M3 | M3 |
| SSobj (190 `START_PROCESSING` sites), SSprocessing, SSfastprocess users, SSbellies, SSburning, SSmaterial_services | Watches, timers, rate models, or declared continuous work | S4 |
| Every machine auto-starting in `Initialize()` (`machinery.dm:140`) | Machines start asleep and declare their activation | S5 |

As built (S3):
- **Airlocks and doors.** `close_door_at`, `main_power_lost_until`, `backup_power_lost_until` and
  `electrified_until` share one `REACT_AT` on the earliest (`next_door_deadline()`,
  `schedule_door_timer()`); `door_deadlines_due()` is the old poll body. Airlocks publish
  `REACT_KEY_DOOR_MODE` (`REACT_DOOR_BOLTS`/`POWER`/`ELECTRIFIED`). `airlock_control.dm`'s
  `cur_command` retry is not a deadline and still processes while a command is pending.
- **Cameras.** EMP recovery and the motion-alarm delay are one `REACT_AT`; losing a motion target is
  signals on the target (moved, stat change, deleted) instead of a per-tick range check.
- **Lights.** `/area/proc/power_change()` publishes `REACT_KEY_AREA_POWER`; lights subscribe and
  act only when their own power changed (`light/power_change()` is a no-op, so the area's scan of
  its machines no longer reaches them). Emergency discharge, recharge and the auto-flicker recheck
  are one `REACT_AT`; an auto-flicker light on its cell waits on the player chunk keys within 12 tiles.
- **Status displays.** Redraw on a signal, alert, power change or `REACT_KEY_SHUTTLE_SCHEDULE`
  (`REACT_SHUTTLE_EVAC`/`SUPPLY`, published when a countdown starts or stops or a shuttle warms up),
  plus one `REACT_AT` only for content that moves by itself (a countdown, the clock at the next
  station minute, a scrolling message).
- **Looping sounds.** Each loop is a `REACT_AT`; a loop nobody can hear parks on the
  `REACT_KEY_PLAYER_CHUNK` keys in hearing range with a 10 s recheck timer. SSsounds'
  `dormant_loops_by_chunk` is gone.
- **Shutoff valves.** `wake_automatic_shutoff_valves(network)` publishes `REACT_KEY_PIPE_NETWORK`
  for that network (`REACT_ID_GLOBAL` for construction of unknown network); each valve subscribes
  to its two networks' keys and the global one and re-subscribes on `reassign_network()`,
  `rust_bind_pipe_port()` and `disconnect()`. SSair's bulk-blast batching is gone: publications merge.
- **Player chunk keys.** `REACT_KEY_PLAYER_CHUNK` (id `MOB_CHUNK_NUMERIC_KEY`) is published by
  `/mob/Moved()` for mobs with a client, only while `SSreactor.player_chunk_subscriptions` is
  non-zero; subscribe with `SSreactor.subscribe_player_chunks()`. Looping sounds and auto-flicker
  lights use it. S2's `REACT_KEY_MOB_CHUNK` covers any mob (AI, turrets); the two could merge
  into one key with a player mask bit once both land.
- **Lint.** `tools/ci/check_deadline_polling.py` (CI: "Check Deadline Polling") flags `process()`
  bodies comparing `world.time` with a variable. The rest (S4's SSobj/SSprocessing users and S5's
  machines) are in `tools/ci/deadline_polling_allowlist.txt`; a stale entry fails the check.

## 10. Lint rules

| Rule | On after |
|---|---|
| No `world.time` deadline comparisons inside `process()` (`tools/ci/check_deadline_polling.py`) | S3 (on) |
| No `START_PROCESSING`/`STOP_PROCESSING`/`START_MACHINE_PROCESSING` outside the reactor | S4, S5 |
| No `process()` unless it is declared with `REACT_EVERY` | S5 |
| No string-built reactive keys | S2 |
