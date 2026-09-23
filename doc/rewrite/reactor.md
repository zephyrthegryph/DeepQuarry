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
/// Called when a subscription fires. `reason` is a mask of channels or event kinds;
/// `source` identifies what changed (a handle, key or timer id).
/datum/proc/react(reason, source)

REACT_ON(src, handle, CH_GAS_PRESSURE|CH_GAS_TEMPERATURE)   // channel change on a Rust entity
REACT_WHEN(src, CONDITION)                                   // a condition watch (Threshold, Band, Difference, …)
REACT_AT(src, world.time + 10 SECONDS)                      // one-shot timer at tick precision
REACT_EVERY(src, 2 SECONDS, "why this is continuous")      // declared continuous work
REACT_PUBLISH(key, mask)                                     // DM-owned state changed
REACT_ON_KEY(src, key, mask)                                 // subscribe to DM-owned state
REACT_CANCEL(src, token)                                     // drop one subscription or timer
REACT_CLEAR(src)                                             // drop everything; called by the base Destroy()
```

- **One registry index per subscriber.** A subscriber holds only that index, a single number. The subscriptions themselves live in Rust ([rust_core.md §6-7](rust_core.md#6-channels-and-watches)), so datums carry no lists.
- **Idempotent `react()`.** The same subscriber is woken at most once per lane per tick, with its reasons merged. Handlers must cope with spurious and merged wakes: read the current state, never count wakes.
- **Handlers never sleep.** Long work goes to a job or an async callback.
- **Cleanup.** The base `/datum/Destroy()` calls `REACT_CLEAR`.

## 2. The continuous lane

A few things really do change every tick while they are active: the supermatter, projectiles, and some mob life systems until the body rewrite's hibernation lands.
- **Declared, never defaulted.** Continuous work is registered with `REACT_EVERY` and a one-line justification. The declaration shows up in the profiler.
- **Scaled by elapsed seconds** (AGENTS.md §3e), so sleeping and waking never change rates.
- **Self-cancelling.** It stops itself with `REACT_CANCEL` once its sleep condition holds.

## 3. Timers

- The timer wheel lives on the main side, in Rust. Inserting and cancelling take constant time, and no datum is created per timer.
- Timers fire at tick precision.
- `REACT_AT` replaces deadline polling: airlock `close_door_at`, `main_power_lost_until` and `electrified_until`, camera EMP recovery, cooldowns.
- SStimer stays for general callbacks until S4 moves the heavy users. Its per-insert debug list is fixed first (fixes.md Q10).

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

## 7. Missed-wake safety and metrics

- **Wake tests.** Every subscriber type gets a wake test: change its input and check it woke; hold the input steady and check it stays asleep. This extends the pattern the body rewrite uses.
- **Audit.** A debug audit samples sleeping subscribers and logs any whose sleep condition no longer holds. This replaces `audit_reactive_sleepers`, which has no callers today.
- **Metrics.**
  - Wakes by type and reason class (bounded).
  - Continuous-lane cost by type.
  - Timer counts.
  - Dispatch time.

  The profiler and the benchmarks read them. Today's `machine_wake_reason_counts`, which grows all round (B4), is replaced.

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

## 10. Lint rules

| Rule | On after |
|---|---|
| No `world.time` deadline comparisons inside `process()` | S3 |
| No `START_PROCESSING`/`STOP_PROCESSING`/`START_MACHINE_PROCESSING` outside the reactor | S4, S5 |
| No `process()` unless it is declared with `REACT_EVERY` | S5 |
| No string-built reactive keys | S2 |
