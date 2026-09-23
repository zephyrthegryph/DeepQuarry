# Medical frameworks: clocks, ownership, nullspace, exposure

Status: design, approved in outline by the user. No gameplay code lands with this document.
Baseline: `master` at `59ca56beef`. Every `file:line` below is from that tree.

This is the body rewrite's plan for four frameworks. It is written for a team of agents to
implement directly. Each framework gives its data structures and procs, the file layout, the
migration split into slices with disjoint file ownership, tests, lints, and the exact list of
what we need from the other session (the containment, reactor and rules rewrite described in
`doc/rewrite/`). Section 5 is the joint work list, and section 6 is the dependency-ordered wave
plan.

Read with: `AGENTS.md`, `doc/body_architecture.md`, `doc/mob_life_architecture.md`,
`doc/rewrite/containment.md`, `doc/rewrite/reactor.md`, `doc/rewrite/roadmap.md`.

**Ownership vocabulary.** "Ours" means the body rewrite's areas: body, medical, organs,
surgery, reagents' effects on mobs, mob life, resleeving, vore's effects on mobs, proteans,
robots' bodies. "Theirs" means the other session's areas: containment, the reactor, properties
and rules, interactions, damage packets, temperature, machines, items in general.

---

## 0. Summary

| # | Framework | One-line rule | Replaces |
|---|---|---|---|
| 1 | Holder-provided clocks | Time-based state is a rate on a clock that the holder supplies, and it is settled when read. Nothing time-based in our areas calls `process()` or `addtimer` directly. | 60+ `process()`/`START_PROCESSING`/`addtimer` sites; `preserved` flags; `advance_stasis()` cycle skipping; `life_wake_in`'s SStimer |
| 2 | Ownership, with ordered destruction | Limbs, organs, implants, embedded objects, cavity items, splints and tourniquets are ledger contents in a nested tree. Attaching and detaching happen only through ledger moves, with one hook pair doing the bookkeeping. A holder's contents drop before its own teardown starts. | `organs`, `organs_by_name`, `internal_organs`, `internal_organs_by_name`, `children`, `implants`, `embedded` and the other hand-kept lists; the six copies of teardown order |
| 3 | Nullspace elimination | Only deletion puts an atom in nullspace. Everything else lives inside the physical thing it belongs to. | 59 `moveToNullspace`/`loc = null` sites, and the `!loc` guards that exist because of them |
| 4 | Exposure (pharmacology) | A reagent reaches the body by a route into compartments, is absorbed and cleared at rates on the body clock, and acts only through one `effective_dose()` that applies every gate. Its effects are data. | ~395 `affect_*`/`overdose` overrides; 9 known reagent bugs |

---

## 1. Holder-provided clocks

### 1.1 Why

Time-based body state today runs on four unrelated mechanisms. None of them knows about the
others.

- **SSobj `process()` for detached parts.** An organ starts processing when it is removed
  (`code/modules/organs/organ.dm:476`), stops when it is implanted (`organ.dm:521`), stops when
  it dies (`organ.dm:146`), and restarts on necrosis surgery (`organ_external.dm:291`,
  `organ.dm:585`). While detached, `process()` rots it, grows germs and ticks the afflictions
  it carries (`organ.dm:160-211`, `body/parts/limb.dm:124`).
- **Life ticks for attached parts.** The organs life system calls `process()` on every
  internal organ, and on external organs that need it (`human_organs.dm:45-62`). It is the same
  proc, reached a second way.
- **`preserved` flags written by containers.** Freezer crates (`crates.dm:319-333`), freezer
  boxes (`boxes.dm:524-538`), cryobags (`bodybag.dm:216-242`), the organ gripper
  (`robot_simple_items.dm:712-726`) and the MMI (`MMI.dm:37,147`) set `preserved` from
  `Entered`/`Exited`, and only one level deep. A brain in a head in a freezer is preserved; a
  brain in a head in a bag in a freezer is not.
- **Fractional cycle skipping for stasis.** `advance_stasis()` (`stasis.dm:27-39`) adds
  `1 - BF_STASIS` per Life cycle and skips whole cycles. Nine readers check
  `inStasisNow()`/`ctx.in_stasis()` to skip their work. Stasis affects only the mob's own Life,
  so a severed limb in a cryobag rots at full speed.

Time units are also inconsistent. `brain.defib_timer` counts Life ticks
(`brain.dm:36-43`, "Life tick happens every ~2 seconds" at `brain.dm:90`). Wound updates run
every `wound_update_accuracy` Life ticks (`organ_external.dm:813`). Tourniquet ischemia uses
world time (`tourniquet.dm:98,113`). Reagent metabolism removes a fixed amount per cycle,
whatever the cycle's length (`_reagents.dm:93`).

### 1.2 The model

A **clock** maps world time to clock time. Every clock is piecewise linear:
`clock_now = base_clock + (world.time - base_world) × speed`. Its speed changes only at
discrete events, such as stasis starting or a freezer losing power, and the clock rebases at
each change.

| Clock | Speed | Owner | Created |
|---|---|---|---|
| World | 1 | `GLOB.world_clock` | Boot |
| Body | `1 - BF_STASIS` (0 when BF_STASIS = 1) | `/datum/body` | Lazily, the first time something clocked attaches or is read |
| Preserver (freezer crate, freezer box, organ gripper, morgue tray) | Per holder type, for example 0.1 | The holder atom | Lazily, on the first clocked insert |
| Stasis container (cryobag, stasis cage, cryopod, MMI's organ cradle) | Per holder, for example 0.01 or 0 | The holder atom | Lazily |

**Resolution.** An object's clock is the clock of the nearest enclosing holder that provides
one. The search walks `loc` upwards, and a turf ends it with the world clock. An organ inside a
limb inside a body uses the body clock. The same limb on the floor uses the world clock. In a
freezer box inside a closet it uses the freezer box's clock. This fixes the one-level-deep
`preserved` bug by construction.

A holder that provides a clock but is itself inside a slower holder composes the two: the
effective speed is the product of the speeds along the chain. For example, a cryobag inside a
freezer runs at 0.01 × 0.1. Composition is computed when binding: a holder clock that has a
parent clock registers as a child of it, and a speed change on the parent rebases its children.
Only clocks that have bound objects are ever created.

**Quantities are rates.** A clocked object declares how its state changes per clock second.
State is settled on read: integrate from the last settle to now at the current rate. Where a
rate depends on other state (temperature, an affliction, a reagent), the rule is: **settle
before any input to a rate changes.** The input's setter calls `clock_settle()` first.

**Thresholds are events.** After a settle, the object computes when its next threshold will be
crossed in clock time (for example, "necrosis reaches 100 in 340 clock seconds") and schedules
that on its clock. The clock turns its earliest pending event into one `REACT_AT` on the
reactor. When the clock's speed changes, it recomputes that one wake. Objects don't reschedule
anything, because their events are stored in clock time.

**Holder change.** The ledger's move hook (section 5, J5; gated by the `move_hooks` bit on the moving thing) calls
`clock_rebind()` on the moving thing and on every clocked descendant: settle at the old clock, cancel its handles, bind the new
clock, then reschedule. There is no per-tick process for unowned objects at all. A severed hand
on a floor costs nothing until someone reads it or its necrosis threshold fires.

**Rule.** Nothing time-based in our areas uses `process()`, `START_PROCESSING` or `addtimer`
directly. There are exactly two ways to run on time:
1. **The holder ticks it.** A body's Life ticks the parts attached to it with
   `ctx.body_seconds`. This is for per-tick simulation that depends on many inputs (organ
   function, wound bleeding, heart rhythm).
2. **It is clocked.** Everything else, such as decay, spoilage, viability, breakdown and
   one-shot delays.

`REACT_AT` and `REACT_EVERY` remain the reactor's primitives. In our areas they are called only
by `/datum/clock` (one token per clock) and by the life scheduler.

### 1.3 Data structures and procs

`code/__defines/clocks.dm`
```dm
#define CLOCK_SPEED_STOPPED 0
#define CLOCK_KIND_WORLD 1
#define CLOCK_KIND_BODY 2
#define CLOCK_KIND_HOLDER 3
/// A handle is (serial * 16) + (clock kind); 0 is "no handle". Stale handles never cancel newer events.
#define CLOCK_NO_HANDLE 0
/// Seconds of world time as clock seconds at `speed`.
#define CLOCK_SECONDS(ds) ((ds) / (1 SECONDS))
/// Probability for an event with chance `p_nominal` per nominal Life cycle, over `seconds`.
#define PROB_OVER(p_nominal, seconds) (100 * (1 - (1 - (p_nominal) / 100) ** ((seconds) / LIFE_NOMINAL_SECONDS)))
```

`code/datums/clocks/clock.dm`
```dm
/datum/clock
	var/kind = CLOCK_KIND_HOLDER
	/// Clock seconds per world second, after composing with the parent clock.
	var/speed = 1
	/// This clock's own factor (a freezer's 0.1); speed = own_speed * parent.speed.
	var/own_speed = 1
	var/base_world = 0      // world.time at the last rebase (deciseconds)
	var/base_clock = 0      // clock reading at the last rebase (clock seconds)
	/// Weakref-free: the provider nulls this in its Destroy (1.6).
	var/datum/provider
	var/datum/clock/parent
	/// Lazy: child clocks composed on this one.
	var/list/children
	/// Lazy: pending events, "[handle]" -> list(at_clock, datum/target, proc_ref, arg).
	var/list/events
	/// Lazy: target -> list of its handles (for cancel_all).
	var/list/handles_by_target
	var/next_serial = 0
	/// The single REACT_AT token for the earliest event, or null.
	var/react_token
	var/react_at_clock      // clock time that token was set for

/datum/clock/proc/now()                                     // clock seconds
/datum/clock/proc/set_own_speed(new_speed, reason)          // rebase, recompose children, rearm
/datum/clock/proc/rebase()                                  // base_* := now
/datum/clock/proc/schedule(datum/target, at_clock, proc_ref, arg) // -> handle
/datum/clock/proc/schedule_in(datum/target, clock_seconds, proc_ref, arg) // -> handle
/datum/clock/proc/cancel(handle)                            // TRUE if it was pending
/datum/clock/proc/cancel_all(datum/target)
/datum/clock/proc/world_time_of(at_clock)                   // null when speed is 0
/datum/clock/on_react(reason, source, source_kind)          // fire every due event, then rearm
/datum/clock/proc/rearm()                                   // REACT_CANCEL old token; REACT_AT the earliest
/datum/clock/Destroy()                                      // detach children to parent, cancel all, REACT_CLEAR
```
- Events fire in clock-time order. A handler may schedule or cancel events, and `on_react()`
  loops until nothing is due. Handlers are `SIGNAL_HANDLER`-style: they must not sleep, and
  slow work goes to `INVOKE_ASYNC`.
- A clock at speed 0 holds no reactor token. Its events stay parked until the speed rises.
- `rearm()` guards against past deadlines. A past deadline fires on the next reactor step
  (`reactor.md` §3).
- Logging: `CLOCK:` lines for speed changes (`reason`), for rebinds when `GLOB.clock_trace` is
  on, and for events that fire more than one reactor step late.

`code/datums/clocks/clocked.dm`, the object side (on `/atom/movable`, since only atoms have
holders):
```dm
/atom/movable
	/// The clock this object's time-based state is settled against, or null when not clocked.
	var/tmp/datum/clock/bound_clock
	/// Clock reading at the last settle.
	var/tmp/clock_settled_at = 0
	/// Pending threshold handle(s) on bound_clock. A number, or a lazy list when several.
	var/tmp/clock_handles

/// Types that carry clocked state return TRUE (a static per-type answer; also adds TAG_CLOCKED
/// (dynamic; ledger_refresh_contribution() on change, J7) and sets MOVE_HOOK_CLOCK in move_hooks, J5).
/atom/movable/proc/is_clocked()
/// Bind to the holder clock now (Initialize, or the first read).
/atom/movable/proc/clock_bind()
/// Integrate to now. Calls on_settle(seconds) with the clock seconds elapsed since the last settle.
/atom/movable/proc/clock_settle()
/// Type hook: advance state by `seconds` at the current rates. Must be exact for any split of
/// the interval (settle(a)+settle(b) == settle(a+b)); use closed forms, not Euler steps.
/atom/movable/proc/on_settle(seconds)
/// Type hook: after a settle, schedule the next threshold with clock_schedule_in(). Default none.
/atom/movable/proc/clock_next_threshold()
/// Settle, drop handles, bind to `new_clock` (null: resolve from loc), reschedule.
/atom/movable/proc/clock_rebind(datum/clock/new_clock)
/atom/movable/proc/clock_schedule_in(clock_seconds, proc_ref, arg)
/// Nearest enclosing clock provider's clock (walks loc; turf -> GLOB.world_clock).
/atom/movable/proc/holder_clock()
/// Holders that provide a clock override this (returns their lazily made clock).
/atom/proc/provided_clock()
```
`/atom/movable/Destroy()` in the pre-destroy phase (J1) calls
`bound_clock?.cancel_all(src)`, then nulls `bound_clock`.

**Body clock.** `code/modules/body/clock.dm`:
```dm
/datum/body
	var/tmp/datum/clock/body_clock
/datum/body/proc/get_clock()               // lazy; kind BODY; parent = owner's holder clock
/datum/body/proc/sync_clock_speed(reason)  // own_speed = 1 - get_factor(BF_STASIS)
/mob/living/provided_clock()               // body.get_clock()
```
`recompute_factors()` (`factors.dm:244`) calls `sync_clock_speed("stasis")` when BF_STASIS
changes. The body clock's parent is the mob's holder clock. A body in a freezer is therefore
slowed by the freezer as well as by its own stasis, with no separate stasis source needed for
cold storage.

### 1.4 Stasis replaces `advance_stasis()`

`Life()` gains a body-time delta. It stops skipping cycles:
```dm
// scheduler.dm, Life():
var/datum/life_context/ctx = new(seconds, profile)
ctx.body_seconds = body ? body.life_advance(seconds) : seconds
```
`/datum/body/proc/life_advance(seconds)` settles the body clock and returns
`seconds × speed`. With a parent clock, the result is `seconds × composed speed`, which is the
same value `body_clock.now()` advanced by since the last cycle.

- Every body-time life system (chemicals, breathing, blood, afflictions, organs, hunger)
  scales by `ctx.body_seconds`, and chance-per-cycle effects use `PROB_OVER(p, body_seconds)`.
  At stasis 0.9 each system does one tenth of the work every cycle, instead of all the work
  every tenth cycle. Totals are the same, and there is no stutter.
- At `body_seconds == 0` the body-time systems return `LIFE_SLEEP`. With nothing else awake,
  the mob hibernates, and stasis 1 costs nothing.
- Deleted: `stasis_clock`, `stasis_paused`, `advance_stasis()` (`stasis.dm:19-39`),
  `/mob/proc/inStasisNow()` and `/mob/living/inStasisNow()` (`stasis.dm:42-46`),
  `ctx.stasis`/`ctx.in_stasis()`, and the readers: `body.dm:357`, `human/life.dm:367`,
  `human/life.dm:1250`, and every other `inStasisNow()` caller (lint J-K2 forbids new ones).
- The `/datum/modifier/stasis` family (`stasis.dm:52-121`) stays as the source of BF_STASIS.
  `set_stasis()` stays.

### 1.5 Hibernation and `life_wake_in`

`life_wake_in(bits, delay)` (`scheduler.dm:171-188`) currently uses SStimer through
`addtimer(... TIMER_STOPPABLE)`. It gets a clock argument:
```dm
/mob/living/proc/life_wake_in(bits, delay, clock_kind = CLOCK_KIND_WORLD)
```
- **World kind.** Used for client-facing rechecks such as ambience (`living_systems.dm:412`)
  and movement (`living_systems.dm:441`). It schedules on `GLOB.world_clock`, which is one
  `REACT_AT` through the clock.
- **Body kind.** Used by any system whose `rewake_delay()` means "this body process drifts
  slowly", such as regeneration and blood refill. It schedules on `body.get_clock()`, so stasis
  stretches the delay and total stasis parks it.
- One handle per mob per kind replaces `life_timer_id`/`life_timer_at`/`life_timer_bits`.
  `clear_life_systems()` (`scheduler.dm:122-133`) cancels both.
- `/datum/life_system/proc/rewake_delay()` becomes
  `rewake(mob/living/self) -> list(delay, clock_kind)` or null. The two current overrides are
  world kind.
- A hibernating body is still correct: its clock keeps running, so anything read while it
  sleeps settles to now, and its threshold events still fire through the reactor. Hibernation
  stops only per-tick simulation, and that is already asleep by definition.

### 1.6 Scheduler API and cancellation on deletion

- A handle is a number. `clock.cancel(handle)` is O(1) (assoc removal), plus a `rearm()` only
  when the cancelled event was the earliest.
- **Cancel on the target's deletion.** A `/atom/movable` target is cancelled from the
  pre-destroy phase (1.3). A `/datum` target that is not an atom (an affliction, a component)
  must call `clock.cancel_all(src)` in its `Destroy()`. The body does this for its afflictions
  in `remove_affliction()`. As a backstop, `on_react()` skips and logs any event whose target
  is `QDELETED`.
- **Cancel on the clock's deletion.** Its bound objects rebind to the parent clock. Events
  move with their objects through `clock_rebind()`, not with the clock. The provider nulls
  `clock.provider` and qdels the clock at the end of its own teardown. By then the ledger has
  moved its contents out (J1), and they have already rebound.

### 1.7 Clocks and the reactor

The reactor is the other session's single scheduler (`reactor.md` §1). Clocks are one of its
clients and do not duplicate it:

| Concern | Owner |
|---|---|
| Delivering a wake at a world time | Reactor: `REACT_AT`, one token per clock |
| Mapping clock time to world time, and parking at speed 0 | Clock |
| Ordering many events on one clock | Clock (its assoc list plus the earliest-event scan) |
| Continuous work (`REACT_EVERY`, and `REACT_PROCESS` once the other session lands it; it is not on `master`) | Reactor. Never used for clocked quantities. |
| Rates that simulation drives (power, fuel) | Reactor's Rust rate models (`vg_rate_*`, `REACT_RATE`) |
| Rates on a holder clock (decay, spoilage, viability, breakdown) | Clock settle, in DM |

Why clocked quantities don't use the Rust rate models: those run on world time. A holder clock
would have to rewrite every model's rate on each speed change, which is O(bound objects) FFI
calls per freezer power flicker. A DM settle is O(1) and happens only when the state is read.
If a `REACT_PROCESS` job ever needs a body-time quantity, it reads it through
`clock_settle()`. There is one writer (`README.md` principle 5).

### 1.8 Classification: body time or world time, for every timed thing in our areas

"Body" means it runs on the part's holder clock: the body clock while attached, or the
container's clock while detached. "World" means the world clock. "Holder-ticked" means it runs
inside Life with `ctx.body_seconds`.

| Timed thing | Today | Clock | New home |
|---|---|---|---|
| Detached organ rot (necrosis lesion growth) | `organ.dm:193-196` in SSobj `process()` | Body (holder) | `obj/item/organ/on_settle()`: necrosis rate × seconds; threshold "organ dies" |
| Detached organ germ growth | `organ.dm:197-199` | Body (holder) | `on_settle()` closed form; threshold INFECTION_LEVEL_THREE → `die()` |
| Detached organ blood drip (`blood_splatter` 40%) | `organ.dm:188-192` | World | Cosmetic. Drop it, or make it a world-clock event every N seconds while blood remains |
| Afflictions riding a detached part (`tick_offline`) | `limb.dm:124-129`, `affliction.dm:262-265` | Body (holder) | Settled by the part's `on_settle()`: `A.settle_offline(seconds)` (linear, exact) |
| Attached organ function (heart, lungs, liver, kidney, eyes, spleen, appendix, brain) | `human_organs.dm:45-46` → each `process()` | Holder-ticked | `/obj/item/organ/proc/life_tick(datum/life_context/ctx)`, called by the organs system with `ctx.body_seconds`. The `process()` overrides are renamed (see 1.9). |
| Attached wound updates and bleeding | `organ_external.dm:808-819`, `human_organs.dm:55-76` | Holder-ticked | `life_tick(ctx)`, scaled by seconds |
| Trace chemicals fading | `organ_external.dm:815-819` (every 10 life ticks) | Body | `on_settle()`: linear decrement × seconds |
| Brain defib window (`defib_timer`, in ticks) | `brain.dm:20-43`, `mmi_holder` `machine.dm:65` | Body | `brain.revival_window` in clock seconds, falling while dead and recovering while alive. Threshold "window closed" |
| Tourniquet ischemia | `tourniquet.dm:98,113` (`applied_at = world.time`) | Body | `applied_at_clock` on the limb's clock. `limb_ischemia` severity rate × seconds |
| Affliction progression, treatment, symptoms | `body.dm:349-365` per Life | Holder-ticked | Unchanged, but scaled by `ctx.body_seconds` (progression per second, not per tick) |
| Reagent absorption, metabolism, clearance | `human/life.dm:1253-1259` → `metabolize()` | Body | Exposure compartments settle on the body clock (framework 4) |
| Hunger | `human/life.dm:1272-1280` | Holder-ticked | Scaled by `ctx.body_seconds` |
| Blood regeneration and loss | blood system (`organs/blood.dm`) | Holder-ticked | Scaled by `ctx.body_seconds` |
| Radiation decay and accumulated rads | `human/life.dm:363-409` (every 5 ticks, "per tick" constants) | Body | Radiation becomes an exposure compartment (4.7): first-order clearance on the body clock |
| Carbon ambient germ creep | `carbon.dm:25-27` | Holder-ticked | Scaled |
| Addiction decay and withdrawal | `withdrawl.dm:1-58` (`prob(8)` per tick) | Body | Addiction level is clocked (linear decay). Withdrawal is an affliction (4.5) |
| Corpse decay (rotting component) | `datums/components/disabilities/rotting.dm` | Body | Clocked on the corpse's body clock, so a morgue tray or cryobag slows it |
| Nanoform dormancy reboot | `nanoform.dm:275` `addtimer(DORMANCY_REBOOT_TIME)` | Body | `body_clock.schedule_in(DORMANCY_REBOOT_SECONDS, complete_revival)`. The affliction cancels it in `Destroy()` |
| Promethean stillness | `prometheans.dm:262` `addtimer(PROMETHEAN_STILLNESS_TIME)` | Body | `body_clock.schedule_in` |
| Vomit warning and act | `living.dm:658-659` (15 s, 25 s) | Body | `body_clock.schedule_in`; nausea is a body process |
| Anomalock heart cooldown and lightning overlay | `heart_anomalock.dm:55,59,75` | World | Cosmetic overlay and ability cooldown. The overlay stays on world time through the world clock; the cooldown becomes a P5 ability cooldown (§5, J12) |
| Cavity implant activation delay | `surgery/cavity.dm:161` (2.5 s) | World | Procedure timing. `GLOB.world_clock.schedule_in` |
| Syringe dirtiness | `syringes.dm:52-56,454` SSobj | World | Clocked on the syringe's holder clock (a syringe in a sterilizer could be clock 0). `dirtiness` rate is `targets.len` per second; threshold 75 |
| Borg hypo recharge | `borghypo.dm:107-113` SSobj | World | Clocked value (recharge rate), read on use. The robot's cell draw is billed on settle |
| Blood bag viability (new) | none (packs never expire) | Body (holder) | Blood reagent `viability` decays on the bag's holder clock; fridges slow it |
| Food spoilage (new, for exposure's ingest route) | none | Body (holder) | Food `freshness` on the holder clock; freezers slow it |
| Reagent breakdown in containers (new) | none | Holder | Unstable reagents declare a `half_life`; a holder's reagents settle on its clock |
| Gib after death animation | `death.dm:42` (2-10 s) | World | Presentation. World clock |
| CPR cooldown | `human_attackhand.dm:143` | World | Interaction cooldown. World clock, or an I-track cooldown (theirs) |
| Life timed wakes (`life_wake_in`) | `scheduler.dm:171-188` | Both | 1.5 |
| Robot killswitch, weapon lock, subversion sequence | `robot.dm:559,576,582,1683` | World | Game-rule timers, not body state. They stay on `addtimer` for now and move to `REACT_AT` in the other session's S4. Listed so the lint allowlist is explicit |
| AI power restore | `ai/life.dm:145` | World | Same as above |
| Cloak, pAI restore, robot animation, thinktank welcome | `cloak.dm:13,16,172`, `pai.dm:479,486`, `robot_animation.dm:15,23`, `thinktank_interactions.dm:68` | World | Presentation. Allowlisted |
| Shadekin dark timers | `shadekin.dm:186,190,192` | World | Ability state. Moves with P5 (J12) |
| Protean rig assimilate and survival gear | `protean_rig.dm:85`, `protean_species.dm:183` | World | One-tick deferrals. Replaced by direct calls once ownership (framework 2) orders creation |
| Dogborg sleeper | `dog_sleeper.dm:142,172,351,633` SSobj | Body (occupant) | It is an occupant holder: provides a stasis-capable clock and ticks its occupant through C8 occupant behaviour (wave H) |
| Grab processing in movement | `living_systems.dm:434-435` `G.process()` | Holder-ticked | Already ticked by the holder. It is renamed `G.life_tick(ctx)` so the lint doesn't see a `process()` |
| Simple mob organ `OR.process()` | `simple_mob/life.dm:290,293` | Holder-ticked | `life_tick(ctx)` |

### 1.9 Inventory: every `process()`, `START_PROCESSING` and `addtimer` in our areas

Scope: `code/modules/{body,organs,medical,surgery,reagents}` and the mob life code
(`code/modules/mob/living/**` outside `simple_mob/subtypes/**`, whose combat patterns such as
`bullet_heck/*` stay game-rule timers).

| Site | Kind | New home |
|---|---|---|
| `organs/organ.dm:146` STOP in `die()` | processing | Deleted. A dead organ's decay continues through settle, and its necrosis rate is set by status |
| `organs/organ.dm:160-211` `/obj/item/organ/process()` | process | Split in two. The detached branch becomes `on_settle()` plus `clock_next_threshold()`. The attached branch (`owner` set: antibiotics, rejection, germ effects, infection bridge) becomes `life_tick(ctx)` |
| `organs/organ.dm:476` START in `removed()` | processing | Deleted. Detaching is a ledger move, and the move hook rebinds the clock |
| `organs/organ.dm:521` STOP in `replaced()` | processing | Deleted, for the same reason |
| `organs/organ.dm:585` START (necrosis cleared) | processing | `clock_settle()` then `clock_next_threshold()` |
| `organs/organ_external.dm:291` START (bioregen) | processing | Same as above |
| `organs/organ_external.dm:808` `external/process()` | process | `life_tick(ctx)` when attached, `on_settle()` when detached |
| `organs/internal/{appendix:13, lungs:8, kidneys:8, liver:7, eyes:81, spleen:11, brain:20}` | process overrides | `life_tick(ctx)` overrides (renamed). `brain` defib ticking moves to the clocked `revival_window` |
| `organs/internal/horror.dm:12,29,53,76,120,141,162,182,200,240` | process overrides | `life_tick(ctx)` |
| `organs/internal/malignant/malignant.dm:104,176,234,278,358,405,437,613,715` | process overrides | `life_tick(ctx)`. Tumour growth is a rate, scaled by seconds |
| `organs/subtypes/{slime:71,117, diona:154, unathi:33}`, `organs/misc.dm:11` (borer) | process overrides | `life_tick(ctx)` |
| `organs/internal/special/heart_anomalock.dm:55,59,75` | addtimer | World clock (overlay) plus a P5 cooldown |
| `body/plans/nanoform.dm:275` | addtimer | Body clock (1.8) |
| `surgery/cavity.dm:161` | addtimer | World clock |
| `reagents/reagent_containers/syringes.dm:52,55,454` | process and processing | Clocked (1.8) |
| `reagents/reagent_containers/borghypo.dm:107,110,113` | process and processing | Clocked (1.8) |
| `reagents/machinery/{pump:80, distillery:300, dispenser2_energy:7, chem_synthesizer:258, bunsen_burner:122}` process; `chem_synthesizer.dm:632,666,690`, `grinder.dm:138` addtimer | machines | **Theirs** (machines, S5). Not in our slices |
| `reagents/reactions/_reactions.dm:85` `chemical_reaction/process()` | not a timer (name collision) | Renamed `react_step()` so the lint doesn't match |
| `mob/living/life/scheduler.dm:180` | addtimer | 1.5 |
| `mob/living/life/living_systems.dm:435` `G.process()` | holder-ticked | `G.life_tick(ctx)` |
| `mob/living/carbon/human/human_organs.dm:46,62` | holder-ticked | `life_tick(ctx)` |
| `mob/living/simple_mob/life.dm:290,293` | holder-ticked | `life_tick(ctx)` |
| `mob/living/simple_mob/life.dm:331` update-icon debounce | addtimer | World, presentation. Allowlisted |
| `mob/living/death.dm:42`, `living.dm:658,659`, `human_attackhand.dm:143`, `human/life.dm:914` (exhale sound) | addtimer | 1.8 rows. `life.dm:914` is presentation: world clock |
| `mob/living/inventory.dm:64`, `living_movement.dm:328`, `say.dm:467` | addtimer | Not body time. Presentation or movement: allowlisted (theirs to convert in S4) |
| `mob/living/carbon/human/species/station/prometheans.dm:187,262` | addtimer | `:187` is a one-tick gib deferral → direct call after the ordered-destruction work. `:262` → body clock |
| `mob/living/carbon/human/species/shadekin/shadekin.dm:186,190,192` | addtimer | P5 (J12) |
| `mob/living/carbon/human/species/station/protean/{protean_rig.dm:85, protean_species.dm:183}` | addtimer | Direct calls (1.8) |
| `mob/living/carbon/human/species/virtual_reality/avatar.dm:125` | addtimer | World clock (VR cleanup is a rule timer) |
| `mob/living/carbon/human/species/lleill/lleill_items.dm:122` | addtimer | Presentation, allowlisted |
| `mob/living/silicon/robot/{cloak.dm:13,16,172, robot.dm:559,576,582,1683, robot_animation.dm:15,23, robot_bellies.dm:50, robot_items.dm:493,496}`, `silicon/pai/pai.dm:479,486`, `silicon/ai/{life.dm:145, malf.dm:53,55}` | mixed | `robot_items.dm:493/496` (SSobj) → clocked or holder-ticked by the robot body. The rest: world rule and presentation timers, allowlisted for S4 |
| `mob/living/silicon/robot/dogborg/dog_sleeper.dm:142,172,351,633` | processing | Wave H (occupant behaviour) |

### 1.10 File layout

```
code/__defines/clocks.dm                 defines, PROB_OVER
code/datums/clocks/clock.dm              /datum/clock, GLOB.world_clock
code/datums/clocks/clocked.dm            /atom/movable clocked API, holder_clock(), provided_clock()
code/datums/clocks/providers.dm          preserver/stasis provider mixin: clock_speed var + provided_clock()
code/modules/body/clock.dm               body clock, life_advance(), sync_clock_speed()
code/modules/organs/organ_time.dm        organ on_settle(), thresholds, life_tick() base
code/modules/unit_tests/dq_clock_tests.dm
code/modules/unit_tests/dq_body_time_tests.dm
```
Include order in `deepquarry.dme`: `clocks.dm` in `__defines`, then `code/datums/clocks/*`
before `code/modules/body/*`.

### 1.11 Migration slices (disjoint file ownership)

| Slice | Owns (and only these files) | Work |
|---|---|---|
| K1 clock core | `__defines/clocks.dm`, `datums/clocks/*`, `unit_tests/dq_clock_tests.dm` | 1.3 and 1.6. Unit tests with the probe `REACT_AT` path |
| K2 body time | `body/clock.dm`, `body/body.dm`, `body/factors.dm` (sync hook only), `medical/stabilisation/stasis.dm`, `mob/living/life/{scheduler.dm,_life_system.dm,living_systems.dm}`, `mob/living/carbon/human/life.dm`, `mob/living/carbon/{carbon.dm,breathe.dm}`, `__defines/life_systems.dm` | 1.4 and 1.5. Every body-time system scales by `ctx.body_seconds`; delete `advance_stasis` and `inStasisNow` |
| K3 organs | `organs/**` except `organs/blood.dm`, plus the new `organs/organ_time.dm` | 1.9 organ rows: `process()` → `life_tick`/`on_settle`; `defib_timer` → `revival_window` |
| K4 providers | `game/objects/structures/crates_lockers/crates.dm` (freezer procs only), `game/objects/items/weapons/storage/boxes.dm` (freezer procs only), `game/objects/items/bodybag.dm` (cryobag procs only), `mob/living/silicon/robot/robot_simple_items.dm` (organ gripper only), `mob/living/carbon/brain/MMI.dm` (`preserved` lines only) | Delete the `Entered`/`Exited` `preserved` writers. Declare `clock_speed`. Delete `var/preserved` (`organ.dm:33`). **Joint:** the first three files are theirs; this slice edits only the named procs, with the other session's agreement (5, J9) |
| K5 misc timers | `body/plans/nanoform.dm`, `mob/living/carbon/human/species/station/prometheans.dm`, `organs/internal/special/heart_anomalock.dm` (overlay part), `medical/stabilisation/tourniquet.dm`, `mob/living/living.dm` (vomit only), `surgery/cavity.dm`, `datums/components/disabilities/rotting.dm`, `reagents/reagent_containers/{syringes.dm,borghypo.dm}`, `organs/blood.dm` | 1.8 rows |

K1 lands first. K2 to K5 run in parallel after it.

### 1.12 Tests

- `dq_clock_tests.dm`
  - **Split invariance.** Settling N times over T gives the same state as settling once over T,
    for every `on_settle` override. A generated test iterates the `is_clocked()` types.
  - **Speed change.** An event scheduled at clock +100 s fires at world +100 s at speed 1. If
    the speed halves at +50 s, it fires at world +150 s, and at speed 0 it never fires.
  - **Composition.** A cryobag in a freezer gives the product speed. When the freezer's speed
    changes, the bag's pending event moves.
  - **Rebind.** An organ moved from a body (speed 0.1) to the floor settles at 0.1 up to the
    move, and at 1 after it.
  - **Deletion.** A qdel'd target's events never fire. A deleted clock's objects rebind to the
    parent, and nothing is lost.
  - **Nested preservation.** A brain in a head in a bag in a freezer rots at the freezer's
    speed. This is the regression test for the one-level `preserved` bug.
- `dq_body_time_tests.dm`
  - **Stasis parity.** Over 100 world seconds at BF_STASIS 0.9, affliction progression,
    metabolism, oxygen debt and blood loss each equal 10 seconds' worth at stasis 0, within
    0.5%. This replaces the cycle-skipping tests.
  - **Total stasis.** At stasis 1 the mob hibernates, and a hand-scheduled body-clock event is
    parked. Releasing stasis wakes it.
  - **`life_wake_in`.** A body-kind wake stretches with stasis. A world-kind wake doesn't.
- Existing tests that read `defib_timer`, `stasis_paused` or `inStasisNow`
  (`dq_mind_host_tests.dm:243`, `dq_body_continuity_tests.dm:341`, `dq_life_scheduler_tests.dm`)
  are migrated by K2 and K3.

### 1.13 Lints (in `tools/ci/check_grep.sh`, or a new `tools/ci/check_body_time.py` with an allowlist ratchet)

1. No `START_PROCESSING`, `STOP_PROCESSING` or `addtimer(` in `code/modules/{body,organs,medical,surgery}/**`.
   `code/modules/reagents/reagents/**` and `code/modules/mob/living/**` use an allowlist file,
   `tools/ci/body_time_allowlist.txt`, listing each 1.9 site marked "allowlisted". A file may
   not gain sites, and a stale entry fails.
2. No `proc/process(` on `/obj/item/organ`, `/obj/item/implant`, `/datum/affliction`,
   `/datum/reagent` subtypes. Holder-ticked work is `life_tick(`.
3. No `inStasisNow`, `stasis_paused`, `advance_stasis`, `preserved` identifiers.
4. No `world.time` inside `on_settle(` bodies or `life_tick(` bodies (use the clock or `ctx`).
5. No `prob(` inside `life_tick(` bodies without `PROB_OVER`. This one is a ratchet: existing
   sites convert slice by slice.

---

## 2. Ownership completed, with ordered destruction

### 2.1 Today

**Where parts physically are.** Every limb and internal organ has `loc == owner`, a flat set
inside the mob. External organs `forceMove(owner)` (`organ_external.dm:359`); internal organs
write `loc = owner` directly (`organ.dm:520`). C3 gave the mob one default interior slot,
`SLOT_ID_BODY` (`body/slots.dm:69-78`), which the ledger fills through legacy `forceMove`
bookkeeping. Implants and shrapnel sit in the mob too (`organ_external.dm:1454`,
`living_defense.dm:236`) while their limb's `implants` list names them. Severed limbs gather
their organs by hand with `loc = src` (`organ_external.dm:1483-1490`).

**The hand-maintained lists and every writer.** A grep of `code/` for `+=`, `-=`, `|=`, `=`,
`.Cut`, `.Add`, `.Remove`, `LAZYADD`/`LAZYREMOVE` on these names finds the following. Pure
readers are not listed; slice O3 converts them with the lists.

| List | Declared | Writers |
|---|---|---|
| `mob/living.organs` | `mob/living/organs.dm:3` | `organ.dm:88,92`; `organ_external.dm:121,125,362,711,714,1106,1497`; `species.dm:488,494`; `species_shapeshift.dm:279`; `butchering.dm:65,66,70`; `living.dm:75-78` |
| `mob/living.organs_by_name` | `mob/living/organs.dm:4` | `organ.dm:90,93`; `organ_external.dm:122,123,361,712,713,1498`; `species.dm:490,496`; `species_shapeshift.dm:280`; `butchering.dm:53`; `living.dm:74`; `protean_powers.dm:284` |
| `mob/living.internal_organs` | `mob/living/organs.dm:2` | `organ.dm:79,83,470,522`; `_organ_internal.dm:21,29`; `organ_external.dm:1397,1401`; `species.dm:489,495`; `mob/living/organs.dm:24,27`; `butchering.dm:80,81,85`; `living.dm:82-86`; `larva.dm:15`; `implantaugment.dm:43,87`; `positive.dm:883`; `protean_reconstitutor.dm:217,225,229,326`; type-default lists `animal.dm:12`, `teppi.dm:133` |
| `mob/living.internal_organs_by_name` | `mob/living/organs.dm:5` | `organ.dm:81,84,467-469,524`; `_organ_internal.dm:22,30`; `organ_external.dm:1395,1396`; `species.dm:491,497,515`; `standard.dm:30-35`; `nanoform.dm:175`; `brain.dm:85`; `surgery/organs.dm:188,231`; `vorepanel.dm:1298`; `butchering.dm:73`; `living.dm:81`; `implantaugment.dm:42,86`; `protean_reconstitutor.dm:213,216,224,228,327` |
| `mob/living.bad_external_organs` | `mob/living/organs.dm:6` | `human_organs.dm:39,42,59`; `organ_external.dm:1467`; `species.dm:492,498` |
| `organ/external.children` | `organ_external.dm:56` | `organ_external.dm:90,102,374,375,718,1493` |
| `organ/external.internal_organs` | `organ_external.dm:57` | `organ.dm:111-113,473,523`; `_organ_internal.dm:24,32`; `organ_external.dm:109,1394`; `horror.dm:399,402,413,415`; `implantaugment.dm:40,41,84,85`; test `dq_medical_damage_model_tests.dm:229,236` |
| `organ/external.implants` (implants, shrapnel and cavity items together) | `organ_external.dm:59` | `organ_external.dm:131,691,1446,1476`; `implant.dm:34,73,118`; `surgery/cavity.dm:97,127`; `mob.dm:1073`; `mop_deploy.dm:73`; `energy.dm:487`; `nif.dm:156,693`; `borer.dm:55` (antag), `borer_powers.dm:148`, `borer.dm:241,300`; `leech.dm:288,311`; `giant_spider/nurse.dm:63`; `effects/spiders.dm:92,107,194`; `reagents/other.dm:955,1130`; `pai_folding.dm:52` |
| `mob/living.embedded` | lazy, `living_defense.dm:236` | `living_defense.dm:236`; `mob.dm:1089`; `mop_deploy.dm:75`; `energy.dm:489` |
| `organ.detached_afflictions` | `limb.dm:15` | `limb.dm:69,77,109,119,128`; `organ.dm:63` |
| `organ/external.parent` | `organ_external.dm:55` | `organ_external.dm:91,371,1494`; `:100` |
| `organ.owner` | `organ.dm:20` | `organ.dm:57,75,163,497,519`; `organ_external.dm:358` |
| `organ/external.splinted`, `.tourniquet` | `organ_external.dm:62`, `tourniquet.dm:56` | `organ_external.dm:111-118`; `tourniquet.dm:96,112` |
| `implant.imp_in`, `implant.part` | `implants/implant.dm` | `implant.dm` (implant/remove), `organ_external.dm:130` |

**How destruction is ordered today.** For a human, the chain (DM runs the latest definition
first; include order is from `deepquarry.dme` lines 3207, 3232, 3271, 5189 and 5433) is:
1. `human/Destroy` (`human.dm:81-99`) qdels every limb from a copy of `organs`. Each limb's
   `Destroy` (`organ_external.dm:87-133`) qdels its children and internal organs. Each organ's
   `Destroy` (`organ.dm:50-65`) **cures** the afflictions on it through `owner.body`, while the
   body is still alive. Parts are deleted, not detached, so `on_detached` bookkeeping never
   runs.
2. `carbon/Destroy` (`carbon.dm:29-35`) deletes the reagent holders.
3. `combat_ai/integration/mob_living.dm:91`.
4. `body.dm:29-31` deletes the body, which removes the remaining afflictions.
5. `living.dm:14-99` runs a second organ-deletion loop (`living.dm:73-86`), which finds the
   lists empty by now.
6. `/atom/movable/Destroy` (`atoms_movable.dm:91-115`) applies drop policies. The body slots
   are `SLOT_DROP_HOLDER` (`body/slots.dm:42`), so equipment is skipped there and qdel'd in the
   plain contents loop after `..()` (`atoms_movable.dm:111-112`), by which point the mob is
   torn down.

The coordinator's gaps, confirmed against the code: subtype `Destroy()` runs before the
ledger's drop policies (gap 1); spilling uses a raw `forceMove` (`api.dm:212-213`) (gap 2,
which is narrower than first reported: the `forceMove` goes through `doMove` →
`note_exit`/`note_enter` at `atoms_movable.dm:366-369`, so `COMSIG_SLOT_REMOVED` and
`on_slot_changed` do fire; only the removal refusal and the pre-signals are skipped); and
`SLOT_DROP_HOLDER` contents are deleted after the holder is gone (gap 3).

**User decisions recorded.**
- The limb tree is physically nested (a hand is inside its arm, and the arm inside the torso),
  and `owner` is derived, not stored.
- The reagent adapter (4.7) exists only on the working branch. W3 and W4 merge to `master`
  together, so `master` never contains it.

### 2.2 The target hierarchy

```
mob/living/carbon/human                      (holder)
 ├─ slot "parts:root"      → torso           (the root limb; one entry)
 │    torso                                  (holder)
 │     ├─ slot "parts:child"   → head, arms, legs, groin
 │     │     arm → slot "parts:child" → hand
 │     ├─ slot "organs"        → heart, lungs, ... (internal organs whose parent_organ is this limb)
 │     ├─ slot "implants"      → implants, NIF, borer, spiderlings
 │     ├─ slot "embedded"      → shrapnel, thrown weapons
 │     ├─ slot "cavity"        → surgically placed items
 │     ├─ slot "splint"        → one splint
 │     └─ slot "tourniquet"    → one tourniquet
 │   head → slot "organs" → brain, eyes
 │            brain (holder) → slot "mind" → /mob/living/carbon/brain view (through mind_host)
 ├─ equipment slots (C3, unchanged)
 └─ SLOT_ID_BODY interior  (bellies, grabs, anything not a part)
```

- **Limbs are a tree, not a flat mob slot.** A limb's children are inside it, so severing an
  arm is one ledger move of the arm's subtree. The hand and the organs, implants, shrapnel and
  cavity items inside it go with it, with no hand-written gathering
  (`organ_external.dm:1478-1490` is deleted).
- **`owner` is derived.** `on_attached` sets `owner` for the whole subtree, and `on_detached`
  clears it. The rule is that `owner` is non-null exactly when the root of the part's tree is
  in a mob's `parts:root` slot. `verify_body_tree()` checks this.
- **Simple bodies** (`/datum/body/simple`) keep no parts. **Robots** keep components as today
  (`plans/machine.dm`). Their MMI moves into a `robot:brain` slot as part of O4.
- **Keyed lookup.** `organs_by_name[tag]` and `internal_organs_by_name[tag]` are hot reads
  (dozens per Life). They become `body.part(tag)` and `body.organ(tag)`, served by a keyed
  index that the ledger maintains for slots declared `keyed` (5, J4). The key is the part's
  `organ_tag`. With a nested tree, the body keeps one flat index,
  `body.part_index[tag] -> part`, whose **only writer** is the attach/detach hook below. The
  ledger stays the source of truth, and `verify_body_tree()` recomputes the index and compares.

### 2.3 Data structures and procs

`code/modules/body/parts/part_slots.dm` (new):
```dm
/datum/slot_def/part                         // abstract: internal exposure, no capacity model
	exposure = SLOT_EXPOSURE_INTERNAL
	drop_policy = SLOT_DROP_DELETE          // see 2.5 for what deletion means for a part
	heat_transmission = 0
	radiation_transmission = 0
	damage_transmission = list(0,0,0,0,0,0,0,0,0,0,0,0) // the body model decides (injure())
/datum/slot_def/part/root       id = SLOT_ID_PART_ROOT     capacity_model = SLOT_CAPACITY_COUNT; capacity = 1
/datum/slot_def/part/child      id = SLOT_ID_PART_CHILD    keyed = TRUE   // accepts external organs whose parent_organ == holder.organ_tag
/datum/slot_def/part/organs     id = SLOT_ID_PART_ORGANS   keyed = TRUE   // accepts internal organs whose parent_organ == holder.organ_tag
/datum/slot_def/part/implants   id = SLOT_ID_PART_IMPLANTS                // /obj/item/implant, /obj/item/nif, parasites
/datum/slot_def/part/embedded   id = SLOT_ID_PART_EMBEDDED  drop_policy = SLOT_DROP_SPILL  // shrapnel falls out
/datum/slot_def/part/cavity     id = SLOT_ID_PART_CAVITY    capacity_model = SLOT_CAPACITY_CUSTOM (surgical_cavity_capacity(), cavity.dm:5)
/datum/slot_def/part/splint     id = SLOT_ID_PART_SPLINT    capacity = 1
/datum/slot_def/part/tourniquet id = SLOT_ID_PART_TOURNIQUET capacity = 1  drop_policy = SLOT_DROP_SPILL
/datum/slot_def/part/mind       id = SLOT_ID_PART_MIND      exposure = SLOT_EXPOSURE_SEALED; drop_policy = SLOT_DROP_CUSTOM (2.6)
/obj/item/organ/external/slot_def_types()  // root/child/organs/implants/embedded/cavity/splint/tourniquet
/obj/item/organ/internal/brain/slot_def_types() // mind
/obj/item/mmi/slot_def_types()                  // mind, plus "brain" for the organ cradle
/mob/living/carbon/human: humanoid plan adds /datum/slot_def/part/root to slot_def_types() (body/slots.dm:293-316)
```

The single hook pair, `code/modules/body/parts/attach.dm` (new):
```dm
/// Ledger hook: `part` (and its subtree) now has `holder` as its container. Called by the ledger
/// after the commit, in the same transaction, for moves into any /datum/slot_def/part slot.
/obj/item/organ/proc/on_attached(atom/holder, slot_id, atom/old_holder)
/// Ledger hook: `part` left `holder`. Called after the commit.
/obj/item/organ/proc/on_detached(atom/holder, slot_id, atom/new_holder)

/// Resolves the mob whose body this part belongs to now (walks the part tree up), or null.
/obj/item/organ/proc/resolve_owner()
/// The whole bookkeeping, run for `part` and every part below it:
/datum/body/proc/adopt_subtree(obj/item/organ/root)   // owner, part_index, attach_part(), verbs, signals
/datum/body/proc/release_subtree(obj/item/organ/root) // detach_part(), index, owner = null, verbs, signals
```
`adopt_subtree` for each part, in tree order (parents first):
1. `part.owner = body.owner`; `part.clock_rebind()` (framework 1), done by the move hook.
2. `part_index[part.organ_tag] = part`.
3. `attach_part(part)` (`limb.dm:115-121`): detached afflictions join the body.
4. `handle_organ_mod_special()`, `refresh_modular_limb_verbs()` and organ verbs.
5. `SEND_SIGNAL(owner, COMSIG_BODY_PART_ATTACHED, part)`.
6. After the subtree: one `invalidate(BODY_DIRTY_ORGANS | BODY_DIRTY_VITALS | BODY_DIRTY_FACTORS | BODY_DIRTY_ARMOR)`, one `UpdateDamageIcon()`/`update_icons_body()` request, and one `life_wake(LIFE_WAKE_BODY, "part attached")`.

`release_subtree` is the mirror, with children processed before parents: `detach_part()`
(`limb.dm:105-112`), index removal, `owner = null`, verbs, signal
`COMSIG_BODY_PART_DETACHED`, then one invalidate, and a vital-part death check
(`organ.dm:488-493` moves here). The transplant data capture (`organ.dm:502-518`) and blood
sampling (`organ.dm:479-486`) move into `on_attached`/`on_detached` respectively.

**Removal procs become ledger moves.** `removed(user)` and `replaced(target, affected)` are
deleted. What calls them now does this instead:

| Operation | Ledger move |
|---|---|
| Sever (`droplimb`, `organ_external.dm:1040`) | `owner.slot_transfer(limb, drop_turf)` for EDGE/ACID. For BURN/BLUNT, move the contents per policy, then `qdel(limb)`. A stump is inserted into the parent's `child` slot (`organ_external.dm:1102-1106`) |
| Surgical removal (`surgery/organs.dm`, `surgery/limbs.dm`) | `limb.slot_remove(organ, user_hand_or_turf, user)` |
| Surgical attach and implant | `organ.move_into(limb, SLOT_ID_PART_ORGANS, user)` |
| Cavity place and remove (`cavity.dm:97,127`) | `move_into(part, SLOT_ID_PART_CAVITY)` and `slot_remove` |
| Embed (`organ_external.dm:1439-1454`, `living_defense.dm:236`) | `W.move_into(limb, SLOT_ID_PART_EMBEDDED)`. Mob-level `embedded` becomes a query over limbs |
| Yank (`mob.dm:1065-1095`) | `limb.slot_remove(W, turf, user)` |
| Implant and unimplant (`implant.dm:34,73,118`, `nif.dm:156,693`) | `move_into(part, SLOT_ID_PART_IMPLANTS)` and `slot_remove` |
| Tourniquet and splint | `apply_tourniquet()` → `move_into(limb, SLOT_ID_PART_TOURNIQUET)`. `limb.tourniquet` becomes a slot read |
| Species change (`species.dm:481-521`) | `create_organs()` deletes the old tree through the normal DELETE path, then builds the new tree parent-first: each part is created at the mob (`new part_type(H)`, never in nullspace) and placed with `move_into()` into its parent's slot. The four `.Cut()`/`= list()` pairs are deleted |
| Robotize with `keep_organs = FALSE` (`organ_external.dm:1389-1398`) | `qdel(thing)`. The pre-destroy phase detaches it |
| Butchering (`butchering.dm:53-85`), horror (`horror.dm:399-415`), protean reconstitutor (`protean_reconstitutor.dm:213-229,326`), augments (`implantaugment.dm:40-43,84-87`), larva (`larva.dm:15`), trait (`positive.dm:883`), nanoform (`nanoform.dm:175`), brain replace (`brain.dm:85`), MMI surgery (`surgery/organs.dm:188,231`), vore revival (`vorepanel.dm:1298`) | Each becomes a `move_into`, `slot_transfer` or `qdel`. List writes are deleted |

**Lists become queries** (`code/modules/body/parts/queries.dm`):

| Old | New |
|---|---|
| `H.organs` | `H.body.parts()`: every external part, in tree order (cached; invalidated by the hook) |
| `H.organs_by_name[tag]` | `H.body.part(tag)` (the keyed index) |
| `H.internal_organs` | `H.body.organs()` |
| `H.internal_organs_by_name[tag]` | `H.body.organ(tag)` |
| `E.children` | `E.slot_contents(SLOT_ID_PART_CHILD)` |
| `E.internal_organs` | `E.slot_contents(SLOT_ID_PART_ORGANS)` |
| `E.implants` | `E.slot_contents(SLOT_ID_PART_IMPLANTS) + SLOT_ID_PART_EMBEDDED + SLOT_ID_PART_CAVITY` through `E.foreign_objects(kinds)` |
| `L.embedded` | `L.body.embedded_objects()` |
| `E.parent` | `E.loc` when it is a part (`E.parent_part()`) |
| `E.splinted`, `E.tourniquet` | `E.slot_item(SLOT_ID_PART_SPLINT)`, `E.slot_item(SLOT_ID_PART_TOURNIQUET)` |
| `H.bad_external_organs` | `H.body.dirty_parts`: a lazy set whose only writer is `body.invalidate_part(part)` (not containment state) |
| `organ.detached_afflictions` | Kept. It is affliction state, not containment. Its only writers are `detach_part`/`attach_part`/`remove_wound` (`limb.dm`) |

Mob types that declare type-default organ lists (`simple_mob/subtypes/animal/animal.dm:12`,
`teppi.dm:133`) are butchering yields, not parts. They are renamed `butcher_organ_types` so they
don't collide.

### 2.4 Ordered destruction: the contract

**Principle.** When a holder is deleted, the ledger first processes its contents per each
slot's drop policy, through the normal detach path, while the holder is still fully valid.
Only then does the holder tear down its own state. There is no teardown mode: detach code
never asks "am I being deleted?".

**The pre-destroy phase** (asked of the other session: J1). `qdel()`
(`controllers/subsystems/garbage.dm:405`) gets a phase before it sets `gc_destroyed`:
```dm
/proc/qdel(datum/to_delete, force = FALSE)
	...                                              // existing type checks (garbage.dm:406-424)
	if(to_delete.datum_flags & DF_PRE_DESTROYING)
		return                                       // re-entrant qdel during the pre phase: ignored
	var/datum/qdel_item/trash = SSgarbage.items[to_delete.type]   // already fetched above (garbage.dm:416)
	if(trash.has_pre_destroy)                        // per-type, on /datum/qdel_item, computed once
		to_delete.datum_flags |= DF_PRE_DESTROYING   // the only instance bit
		SEND_SIGNAL(to_delete, COMSIG_PRE_QDELETING, force)
		to_delete.pre_destroy(force)                 // must NOT set gc_destroyed
		to_delete.datum_flags &= ~DF_PRE_DESTROYING
		if(!isnull(to_delete.gc_destroyed))
			return                                       // qdel(src) inside pre_destroy completed it
	to_delete.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
	...                                              // unchanged: COMSIG_QDELETING, Destroy(), hints
```
- During `pre_destroy()` the holder is **not** `QDELETED`, so `dq_ledger()`, `move_into()`,
  `slot_remove()`, `attach`/`detach` hooks, `owner.body` and signals all work normally.
  `pre_destroy()` never sets `gc_destroyed`. The `QDELETED` bypass in
  `ledger_apply_drop_policies()` (`api.dm:178-192`) is deleted, because release no longer runs
  inside `Destroy()`.
- `dq_ledger_refusal()` refuses moves **into** a holder with `DF_PRE_DESTROYING` ("it is being
  destroyed"), and `latent_add()` refuses it too, so nothing refills it while it empties.
- `ledger.sync()` skips holders with `DF_PRE_DESTROYING`. The alternative, which also works, is
  that every release is a real move out, so `sync()` finds nothing to re-add.
- `/datum/proc/pre_destroy(force)` is a no-op by default. `/atom/movable/pre_destroy()` calls
  `ledger_release_contents(force)`, which drops both the real contents and the **latent
  entries** (today's `drop_latent()` and `ledger_drop_latent()`), and `bound_clock?.cancel_all(src)`
  (framework 1). The call at `atoms_movable.dm:93-94` moves here. `obj_defense.dm:96` is
  `deconstruct(!disassembled)`, not `Destroy`, and does **not** move into `pre_destroy()`.
  `smartfridge.dm:69` is deliberately early, and is simply deleted after J1.
- `qdel_item.has_pre_destroy` is computed per type the first time the type is qdel'd (types with
  `slot_def_types()` or a `pre_destroy()` override), so non-holders pay one field read on an
  object `qdel()` already fetches.
- A unit test proves that `qdel(src)` called inside `pre_destroy()` completes the deletion.
- **Audit of `Destroy()` overrides that read contents.** Before J1 lands, the other session
  lists every holder `Destroy()` that reads its own contents (mech `go_out()`, `component_parts`
  loops, and others). Each one either moves into a CUSTOM drop policy (J3) or is shown not to
  need contents.
- **Hints.** `pre_destroy()` runs whatever `Destroy()` returns later. A holder type that
  returns `QDEL_HINT_LETMELIVE` has already had its contents dropped. None does today: the
  current `LETMELIVE` returners (`datum_pipeline.dm:40`, `weakrefs.dm:66`, `_element.dm:43`,
  `decls.dm:69`, `overlays.dm:139,170`, `misc.dm:146`, `landmarks.dm:96`, `lighting_corner.dm:180`,
  `lighting_overlay.dm:42` and others) hold no slots. A boot check fails any type that declares
  slots and overrides `Destroy()` to return `LETMELIVE` unless `force`. `QDEL_HINT_QUEUE`,
  `HARDDEL` and `IWILLGC` are unaffected.
- **Non-ledger objects.** A plain `/datum` with no `pre_destroy()` override skips the phase
  entirely. A movable with contents but no slots keeps the legacy contents loop
  (`atoms_movable.dm:111-112`) until C11 converts it.

**Spill goes through the API** (J2). Today's spill `forceMove` already reaches the commit
bookkeeping through `doMove` (`atoms_movable.dm:366-369`), so `COMSIG_SLOT_REMOVED` and
`on_slot_changed` fire. What it skips is the removal refusal and the pre-signals. J2 gives
`slot_remove()` a `flags` argument with a `LEDGER_MOVE_FORCED` path, and
`ledger_release_contents()` calls `slot_remove(thing, drop, null, LEDGER_MOVE_FORCED)`.
`FORCED` skips refusals and pre-signals by design, and it runs the same commit bookkeeping plus
the move hook (J5) and the thing hooks (J6). A thing that can't be placed at all is qdel'd, as
today.

**`SLOT_DROP_HOLDER` is phased out** (J3):
- `SLOT_DROP_CUSTOM` and `/datum/slot_def/proc/drop_custom(atom/holder, atom/movable/thing, atom/drop)`
  land now.
- **Body equipment slots** (`body/slots.dm:42`) → `SLOT_DROP_DELETE` (ours). This is today's
  behaviour (the comment at `slots.dm:39-41`), except that equipment is now deleted in the
  pre-phase while the mob is valid, so `unequipped()` hooks see a live wearer.
- **Mech equipment and cargo** (`mecha.dm:281,289`) → `SLOT_DROP_CUSTOM`. Only the spill and
  detach loops move out of the mech's `Destroy()`; `go_out()` stays there.
- **Machine internals** (`stock.dm:19`) convert inside the other session's C6.
- The `SLOT_DROP_HOLDER` define is removed last, together with a lint.

**Destroy ordering for the body**, as the contract every type in our areas follows:
```
qdel(mob)
 ├─ PRE phase (mob valid, body valid, mind attached, afflictions live)
 │   1. COMSIG_PRE_QDELETING on the mob
 │   2. ledger_release_contents(), in slot declaration order:
 │        equipment slots  → DELETE   (unequip hooks run on a live wearer)
 │        parts:root       → DELETE   (torso: on_detached → release_subtree for the whole tree:
 │                                     located afflictions detach into detached_afflictions;
 │                                     index, owner, verbs cleared; then qdel(torso), whose own
 │                                     PRE phase deletes its children/organs/implants the same way.
 │                                     The brain's PRE phase runs its mind slot's CUSTOM policy, 2.6)
 │        SLOT_ID_BODY     → SPILL    (bellies' own PRE phases already released prey, C7)
 │   3. bound_clock.cancel_all(mob); body clock children rebind to the mob's holder clock
 └─ Destroy chain (nothing is left inside the mob)
     human/Destroy  : no organ loop (human.dm:87-89 deleted); NIF is an implant, gone already (human.dm:90-91 deleted)
     carbon/Destroy : reagent holders (exposure compartments, framework 4)
     body.dm        : QDEL_NULL(body) — body/Destroy removes the systemic afflictions only
                      (located ones left with their parts); QDEL_NULL(body_clock)
     living.dm      : organ loops (living.dm:73-86) deleted
     atom/movable   : no drop-policy call; contents are empty (debug: stack_trace if not)
```
Rules this implies:
- `/obj/item/organ/Destroy()` (`organ.dm:50-65`) stops touching `owner.body`. By the time an
  organ's `Destroy()` runs, its PRE phase has detached it (`owner == null`), so its afflictions
  are in `detached_afflictions` and `QDEL_LIST(detached_afflictions)` deletes them. The loop at
  `organ.dm:53-56` is removed.
- `/obj/item/organ/external/Destroy()` (`organ_external.dm:87-133`) keeps only its own state:
  the wound caches and `hud_damage_image`. The children, organ, splint, tourniquet and implant
  loops are deleted, because the ledger dropped them in the PRE phase.
- `/obj/item/organ/internal/Destroy()` (`_organ_internal.dm:19-25`) is deleted.
- **Affliction** `Destroy()` (`affliction.dm:135-140`) stays as it is: it removes itself from
  a body if it is on one, and in the contract above that is only the systemic case.
- **Body** `Destroy()` (`body.dm:82-96`) adds `QDEL_NULL(body_clock)` and asserts
  `!length(afflictions_by_location)` in test builds.
- **Direct `qdel(part)`** (a grenade gibbing a hand, admin delete) runs the part's PRE phase.
  Its container's ledger then sees the exit: `note_exit` → `on_detached` → `release_subtree`,
  **before** the part's own PRE phase deletes its contents. That ordering is J1's second
  requirement: a thing in a slot is removed from its holder's slot, through the hooks, as the
  first step of its own PRE phase.

### 2.5 What "delete" means for a part

`SLOT_DROP_DELETE` on part slots means that the part is detached through the normal path and
then deleted. It is not "cure its afflictions". A deleted body's parts carry their afflictions
into `detached_afflictions` and delete them there. This is observably identical to curing but
has no body side effects: it fires no `COMSIG_BODY_AFFLICTIONS_CHANGED` on a dying body, and
there are no vitals recomputes.

### 2.6 The mind slot and `mind_host`

- `/datum/component/mind_host` (`datums/components/mind_host.dm`) stops using
  `view.forceMove(parent)` (`mind_host.dm:70-71`). `attach_occupant()` becomes
  `view.move_into(parent, SLOT_ID_PART_MIND)`, and `adopt_occupant()` becomes
  `slot_transfer(view, new_host_parent, SLOT_ID_PART_MIND)`.
- The mind slot's `SLOT_DROP_CUSTOM` policy in the PRE phase is:
  1. If the view holds a mind with a client or key, ghostize it with a log line
     (`MIND: [key] released from [host] (host deleted)`). This is today's behaviour, now
     explicit and ordered.
  2. `discard_occupant()` (`mind_host.dm:94-101`).
- `mind_host/Destroy()` (`mind_host.dm:32-41`) keeps only `set_tissue(null)`. The occupant is
  gone by then. It asserts `occupant == null` in test builds.

### 2.7 One revive path: `return_from_death()`

`code/modules/body/revival.dm` (new):
```dm
/// The only way a dead mob becomes alive. Returns TRUE on success, or a reason string on refusal.
/// `source` is what did it (defib, spell, admin, core reboot); `flags` REVIVE_* (REVIVE_HEAL: fully_heal first;
/// REVIVE_IGNORE_WINDOW: skip the brain revival window; REVIVE_KEEP_TIMEOFDEATH).
/mob/living/proc/return_from_death(reason, datum/source, flags = NONE)
```
Order:
1. If `REVIVE_HEAL`, call `fully_heal()` (`injury.dm:252`).
2. Refuse with a reason if `body.is_dead()` still holds, or if the brain's revival window is
   closed and `REVIVE_IGNORE_WINDOW` is not set.
3. `GLOB.dead_mob_list -= src`; `GLOB.living_mob_list |= src`; `timeofdeath = 0`.
4. `set_stat(CONSCIOUS)`, then `body.on_status_changed()`, which lets consciousness settle
   through vitals.
5. `can_defib = TRUE`, `update_hud`, reset perspective.
6. `life_wake(LIFE_SYS_ALL, "revived")`.
7. `SEND_SIGNAL(src, COMSIG_LIVING_REVIVED, source, reason)`.
8. `log_game("REVIVE: [key_name(src)] by [source] ([reason])")`.

Every hand-rolled revive converts to it. The grep for `set_stat(CONSCIOUS)`,
`stat = CONSCIOUS`, `dead_mob_list -=` and `living_mob_list +=` finds:
`living.dm:397` (`revive`), `:420` (`rejuvenate`), `:458-464`; `defib.dm:494`;
`organs/subtypes/machine.dm:18,90-91`; `body/plans/machine.dm:57`; `living_systems.dm:462`;
`human/life.dm:1407`; `MMI.dm:217`; `vorepanel.dm:1239,1330`; `vore/eating/soulcatcher.dm:139`;
`nifsoft/software/13_soulcatcher.dm:239`; `reagents/medicalmods.dm:88-90`;
`mob/_modifiers/horror.dm:585-586`; `changeling/powers/revive.dm:35-36,76-78`;
`changeling/powers/epinephrine_overdose.dm:33`; `technomancer/spells/resurrect.dm:36-38,56-58`;
`xenoarcheaology/effects/resurrect.dm:78-80,101-104`; `robot_upgrades.dm:96-98`;
`human_attackhand.dm:615`; `clothing/gloves/antagonist.dm:135`; `_helpers/unsorted.dm:1218,1224`;
`nanoform.dm:280` (`complete_revival`).
Excluded: `mob.dm:10,90` (list bookkeeping on creation and deletion), `death.dm:11,48,72`,
`human_species.dm:13,25` (death bookkeeping), and `combat_ai/ports/possum.dm:73` (fake death
ending, not a revive).

### 2.8 File layout

```
code/__defines/body_parts.dm            SLOT_ID_PART_*, COMSIG_BODY_PART_ATTACHED/DETACHED, REVIVE_*
code/modules/body/parts/part_slots.dm   slot defs (2.3)
code/modules/body/parts/attach.dm       on_attached/on_detached, adopt_subtree/release_subtree
code/modules/body/parts/queries.dm      parts(), part(), organs(), organ(), embedded_objects(), foreign_objects()
code/modules/body/parts/verify.dm       verify_body_tree(), used by tests and the debug verb
code/modules/body/revival.dm            return_from_death()
code/modules/unit_tests/dq_part_lifecycle_tests.dm
tools/ci/check_part_moves.py (+ tools/ci/part_moves_allowlist.txt)
```

### 2.9 Migration slices

| Slice | Owns | Work | Needs |
|---|---|---|---|
| O1 (other session) | `controllers/subsystems/garbage.dm`, `datums/containment/*`, `__defines/containment.dm`, `game/atoms_movable.dm`, `game/objects/obj_defense.dm` | J1 to J5 | — |
| O2 part slots | `body/parts/{part_slots,attach,queries,verify}.dm`, `__defines/body_parts.dm`, `body/slots.dm` (root slot and `SLOT_DROP_DELETE`), `body/parts/limb.dm` | 2.3 | O1 |
| O3a organs | `organs/organ.dm`, `organs/organ_external.dm`, `organs/internal/_organ_internal.dm`, `organs/organ_stump.dm`, `organs/internal/brain.dm`, `organs/subtypes/standard.dm`, `organs/subtypes/machine.dm` | Delete `removed`/`replaced`, the list writes and the Destroy loops. Convert `droplimb`, `robotize`, `remove_rejuv`, `embed` | O2 |
| O3b mob side | `mob/living/organs.dm`, `mob/living/living.dm` (Destroy loops), `mob/living/carbon/human/{human.dm,human_organs.dm,species/species.dm,species/species_shapeshift.dm}`, `mob/living/butchering.dm`, `mob/living/living_defense.dm` (embed), `mob/mob.dm` (yank), `mob/_modifiers/horror.dm`, `mob/living/carbon/alien/larva/larva.dm`, `species/station/traits/positive.dm` | Lists → queries; species change; embed and yank | O2 |
| O3c surgery and implants | `surgery/**`, `game/objects/items/weapons/implants/{implant.dm,implantaugment.dm}`, `nifsoft/nif.dm`, `medical/stabilisation/tourniquet.dm` | Surgical moves; implants; cavity; tourniquet and splint | O2 |
| O3d proteans and other | `body/plans/nanoform.dm`, `species/station/protean/*`, `game/machinery/protean_reconstitutor.dm`, `vore/eating/vorepanel.dm` (revival block), parasites (`borer*.dm`, `leech.dm`, `giant_spider/nurse.dm`, `effects/spiders.dm`), `reagents/reagents/other.dm:955,1130`, `pai_folding.dm`, `mop_deploy.dm`, `melee/energy.dm` | List writes → moves | O2 |
| O4 destroy and mind | `body/body.dm` (Destroy), `datums/components/mind_host.dm`, `mob/living/carbon/brain/MMI.dm`, `mob/living/carbon/carbon.dm` (Destroy), `silicon/robot` MMI slot | 2.4 to 2.6 | O1, O2 |
| O5 revival | `body/revival.dm`, plus the 2.7 call sites (each a two-to-six-line edit; theirs files like `technomancer`/`xenoarcheaology` are converted with notice) | 2.7 | — (can start at once) |
| O6 harness and lint | `unit_tests/dq_part_lifecycle_tests.dm`, `tools/ci/check_part_moves.py` | 2.10 and 2.11 | O2 |

Parallel after O2: O3a, O3b, O3c, O3d and O4 touch disjoint files. O3b owns the readers in its
files. Readers elsewhere (about 400 `organs_by_name`/`internal_organs_by_name` reads) are
converted by a mechanical codemod pass owned by O6, run last in the wave, after the queries
exist.

### 2.10 The lifecycle test harness

`code/modules/unit_tests/dq_part_lifecycle_tests.dm` is a matrix test.

**Part kinds:** limb with children (arm with hand), leaf limb (hand), internal organ (liver),
brain holding a mind (a test mind with a key), implant (tracking), NIF, embedded shard, cavity
item, splint, tourniquet, and a detached limb carrying afflictions.

**Removal ways:**

| # | Way | How |
|---|---|---|
| 1 | Sever clean | `droplimb(TRUE, DROPLIMB_EDGE)` |
| 2 | Sever blunt | `droplimb(FALSE, DROPLIMB_BLUNT)`: the limb is deleted and its contents spill |
| 3 | Sever burn | `DROPLIMB_BURN` |
| 4 | Surgery | The surgical step procs directly (`surgery/organs.dm`, `limbs.dm`, `cavity.dm`) |
| 5 | Gib | `H.gib()` |
| 6 | qdel of the part | `qdel(part)` |
| 7 | qdel of the holder | `qdel(H)`, and `qdel(limb)` for organs |
| 8 | Digestion | Belly with digest mode; `belly_cycle()` until the mob is gone (C7 path) |
| 9 | Species change | `H.set_species(SPECIES_TAJARAN)` |
| 10 | Mob transform | protean blob ↔ humanoid; `monkeyize` if present |
| 11 | Robotize | `robotize(keep_organs = FALSE)` |
| 12 | Rejuvenate or amputate by prefs | `remove_rejuv()` |
| 13 | Reattach | Remove by 1 or 4, then attach the same part to another human |

**After every step it asserts** `verify_body_tree(H)` plus the following:
- every part whose tree root is in `H` has `owner == H`, and every other part has
  `owner == null`;
- `body.part_index` equals a recomputation, and `parts()`/`organs()` equal a walk;
- every key of `afflictions_by_location` is an attached part, and every located affliction's
  `location.owner == H`;
- every detached part's afflictions are in its `detached_afflictions`, with `A.body == null`;
- no part is in nullspace (`loc != null` unless `QDELETED`);
- the mind is either in the brain's mind slot or a ghost, and never lost (`mind.current` is
  set);
- the clock binding matches the holder chain (framework 1);
- after deletions, the unit-test hard-delete check reports no organ, limb, implant, body or
  affliction hard deletes, and a ref scan (test builds) finds no refs from `H`, `H.body` or the
  parts to deleted parts.

This generates 11 × 13 cases, minus combinations that don't apply (a splint can't be
digested). Each case is its own `TEST_ASSERT` context string, so a failure names the part and
the way.

### 2.11 Lints

- `tools/ci/check_part_moves.py`: in any file, a raw `.loc =`, `forceMove(`,
  `moveToNullspace(` or `contents +=`/`-=` whose receiver's declared type is under
  `/obj/item/organ`, `/obj/item/implant`, `/obj/item/nif`, `/obj/item/tourniquet`,
  `/obj/item/stack/medical/splint`, or a var named `organ|limb|part|implant|E|O` in files under
  `organs/`, `surgery/`, `body/`, is an error. It has an allowlist ratchet.
- `check_grep.sh`: no writes (`+=`, `-=`, `|=`, `[..] =`, `.Cut`, `.Add`, `.Remove`, `= list`) to
  the old list names anywhere, once O3 lands, and no declarations of them.
- No `START_PROCESSING` on those types (shared with 1.13).
- No `set_stat(CONSCIOUS)`, `dead_mob_list -=` or `living_mob_list +=` outside
  `body/revival.dm`, `mob.dm` and `death.dm`.
- No `/obj/item/organ/proc/removed(` or `replaced(` definitions.

---

### 2.12 O2 as built (deviations from 2.2-2.3)

Slice O2 landed on `w6/o2`, on top of the ledger joint (J2 `LEDGER_MOVE_FORCED`, J4 keyed slots,
J6 `on_slotted`/`on_unslotted`, J8 `slot_item`). J1 and J3 did not land; J1 is being replaced by the
framework destroy transaction (`doc/rewrite/lifecycle.md`). Where the code disagreed with the design,
the code won:

- **No `body.part_index`.** The mob-side `organs`, `organs_by_name`, `internal_organs` and
  `internal_organs_by_name` stay as derived caches for O3's readers, and the attach/detach hooks are
  their only writers (every other writer was converted to a ledger move or deleted). A second index
  on the body would have duplicated them. `body.part(tag)`/`body.organ(tag)` read the caches;
  `parts()`/`organs()` walk the ledger. The per-limb `children`, `parent` and `internal_organs`
  also stay, as structural caches written only by `link_to_holder()`/`unlink_from_holder()`,
  maintained whether or not the tree has an owner.
- **The hooks are J6's, not a new ledger hook.** `/obj/item/organ` sets `has_slot_hooks`; its
  `on_slotted()`/`on_unslotted()` call `on_attached()`/`on_detached()` for the three tree slots.
  `on_attached()` resolves the owner by walking up the ledger (`resolve_owner()`); `on_detached()`
  releases from the stored owner.
- **Loose organs on mobs with no tree.** Simple mobs, larvae and butchery animals have no
  `parts:root`. An organ in such a mob's `SLOT_ID_BODY` is attached there (owned and cached), so
  `internal_organs` on those mobs is also hook-maintained.
- **`removed()`/`replaced()` are kept as the entry points** (about 60 callers; converting them is O3),
  but their bodies are now one ledger move each: `slot_remove(..., LEDGER_MOVE_FORCED)` to the owner's
  drop location, and `place_into()` (`dq_ledger_refusal()` + `dq_ledger_commit()`). Organs born inside
  a mob place themselves (`place_in_body()`). Transplant data capture stays in `replaced()`: capturing
  it in the hook would allocate a list for every organ on every spawn.
- **Organ acceptance is lenient.** `parts:organs` accepts any internal organ (surgery, horror
  modifiers and augments put organs in limbs other than their default `parent_organ`); `parts:child`
  enforces `parent_organ == holder.organ_tag`; `parts:root` takes only a limb with no `parent_organ`.
- **Reparent.** A move between two places in the same body (horror's brain shunt) is detach + attach
  in one `forceMove`. `place_into()` marks it (`GLOB.dq_part_reparenting`) so the detach half neither
  runs `left_body()` nor counts a vital loss.
- **Worn equipment.** A hook must not move anything, so gloves, shoes and headgear are dropped by
  `drop_worn()` for the whole subtree before the sever move, in `external/removed()`.
- **Destruction (O4 plugs in here).** Part slots declare `SLOT_DROP_DELETE` (embedded and tourniquet
  `SPILL`), resolved children first. The external `Destroy()` child/organ loops are deleted (the slot
  policy does it); no new `Destroy()` override was added. `release_subtree(root, destroying)` takes
  one early branch when the holder is being destroyed (`dq_part_holder_destroying()`, a stub reading
  `QDELETED(holder)` until the transaction's flag lands): it clears derived state but skips
  invalidate, `life_wake`, verbs, `left_body()` and the death check. `detach_part()` still calls
  `remove_affliction()`, which invalidates once per affliction; O4 should give it a quiet path.
  `organ/Destroy()` still cures afflictions through `owner.body` (2.4's rules are O4's).
- **Body created in `set_species()`.** A human's first `set_species()` runs before
  `/mob/living/Initialize()`, so the body (and with it the humanoid slot set) is now built there;
  `/mob/living/Initialize()` only builds one if none exists.
- **Not done here:** implants, embedded objects, cavity items, splints and tourniquets still live
  where they did (O3b/O3c move them into their declared slots); the mind slot (O4); robot MMI slot
  (O4); the `check_part_moves.py` lint (O6).

## 3. Nullspace elimination

### 3.1 Rule

Only deletion may put an atom in nullspace. `moveToNullspace()` becomes callable only from the
base `/atom/movable/Destroy()` (`atoms_movable.dm:115`). Everything else that is stored lives
inside the physical thing it is tied to, as a ledger entry of that holder. The user has ruled
out a generic "body vault". Where something genuinely has no physical anchor, this section says
so and proposes the smallest fix. It is the other session's C11 in spirit, and they take the
non-body uses and the lint (coordinator's note).

### 3.2 Audit

The audit covers every `moveToNullspace(`, `loc = null` and `forceMove(null)` in `code/`
(59 matches in 46 files), plus the atoms created in nullspace with `new X(null)` (22 matches),
plus the `!loc`/`isnull(loc)` guards (28 matches in 20 files). The "Owner" column says whether
the site is **ours** or **theirs**.

**A. Moves into nullspace**

| # | Site | Why it's there | Replacement | Owner |
|---|---|---|---|---|
| 1 | `game/atoms_movable.dm:115` | Base `Destroy()` | Kept: this is deletion | theirs |
| 2 | `game/atoms_movable.dm:348` (`moveToNullspace` def), `:428` (`doMove` null dest) | The mechanism | Renamed `nullspace_for_deletion()`, callable only from #1 (lint) | theirs |
| 3 | `game/atom/_atom.dm:448` `dropInto` fallback | No valid drop destination | Return FALSE; the caller qdels or keeps it | theirs |
| 4 | `modules/mob/inventory.dm:494` `inventory_release(I, null)` | "Remove from inventory, no destination", used before qdel or re-equip | A null destination becomes a `CRASH`. Callers that are about to qdel call `delete_from_inventory(I)` (ledger remove plus qdel). Callers that re-equip pass the new holder, so the item goes directly to its destination | **ours** |
| 5 | `modules/mob/dead/observer/observer.dm:549` `body_backup.moveToNullspace()` in ghost `Destroy` | The digested prey's body backup rides inside the ghost (`belly_obj.dm:762-764` does `slot_remove(M, G)`) and is dropped into nullspace when the ghost dies | The backup lives in the thing it belongs to. For digestion it is the **belly** that reforms it (`vorepanel.dm:1201-1252` "reformed in [host]"): a sealed `BELLY_SLOT_BACKUP` slot, drop policy DELETE, holder clock speed 0 (so the body neither rots nor ticks; it hibernates). `G.body_backup` becomes a weakref plus a lookup. The ghost's `Destroy` no longer touches it | **ours** |
| 6 | `vore/eating/belly_obj.dm:755-757` (MMI case) `slot_remove(M, hasMMI)` | Backup inside the MMI's contents, untracked | `M.move_into(hasMMI, SLOT_ID_MMI_BODY_BACKUP)`, sealed, clock speed 0. The MMI's drop policy is DELETE, which is today's behaviour but ordered (J1) | **ours** |
| 7 | `mob/dead/observer/observer.dm:96` | No observer spawn point | Fall back to the CentCom observer landmark (z4 always exists on `southern_cross`). In unit tests, `CRASH` | **ours** |
| 8 | `mob/new_player/lobby_browser.dm:113` | Preview observer created inside the mannequin, then yanked out | Create it at its destination directly (`new /mob/observer/dead(spawn_turf)`), or not at all: the preview needs only an appearance, so use a `mutable_appearance` | **ours** |
| 9 | `mob/new_player/login.dm:14` `loc = null` | The lobby mob has no place in the world | **Genuinely no anchor.** Smallest fix: `/mob/new_player` is the one mob type allowed in nullspace, by a type allowlist in the lint and the audit (`NULLSPACE_NATIVE` flag). Justification: it never interacts with the world, and giving it a turf would make it hearable and visible | **ours** |
| 10 | `mob/living/carbon/brain/MMI.dm:153` | Eject with no destination | `destination = drop_location()` always exists once nothing is in nullspace. Remove the branch and assert | **ours** |
| 11 | `mob/living/carbon/human/species/station/protean/protean_species.dm:112` | NIF parked during `create_organs()` | Mid-transfer items go straight to their destination: `saved_nif.move_into(H, SLOT_ID_BODY)` (the mob's interior), then `quick_implant()` into the new head's implants slot. Under framework 2 this becomes one `slot_transfer` from the old head to the new head, done after the new tree is built and before the old one is deleted | **ours** |
| 12 | `modules/mob/mob_grab_specials.dm:188` `src.loc = null; qdel(src)` | Remove the grab object before deleting it | Delete the `loc` write; `qdel` handles it (PRE phase) | **ours** |
| 13 | `modules/organs/organ_external.dm:112` splint `loc = null` in `Destroy` | Splint teardown | The splint is in `SLOT_ID_PART_SPLINT` (DELETE policy). The line is deleted (framework 2) | **ours** |
| 14 | `game/objects/items/robobag.dm:88,93` `corptag.loc = null` | Tag attached to the bag, stored off-map | `corptag.move_into(bag, SLOT_ID_BAG_TAG)` (external, SPILL on destroy) | **ours** (medical equipment) |
| 15 | `game/objects/items/bodybag.dm:282` `syringe.loc = null` | Cryobag's loaded injector syringe | `syringe.move_into(bag, SLOT_ID_BAG_INJECTOR)` (internal, SPILL) | **ours** |
| 16 | `mob/living/living.dm:39` `dsoverlay.loc = null` in `Destroy` | Darksight overlay object carried by the mob | Make it an `/image` or `mutable_appearance` on the client (not an atom). Delete the line | **ours** |
| 17 | `modules/shuttles/crashes.dm:62` `L.loc = null` | Hides the victims during the crash, then restores them | Mobs never enter nullspace. The crash spawns a sealed `/obj/effect/crash_shelter` at the target turf with an occupant slot (C8a occupant slot, `reaches_mobs = FALSE`), puts the victims in, and releases them after. **Joint:** shuttles are theirs, and the mob-side rule is ours | joint |
| 18 | `game/objects/items.dm:183` `src.loc = null` in `/obj/item/Destroy` | Leftover after `drop_from_inventory` | Delete it (PRE phase handles the exit) | theirs |
| 19 | `game/objects/items.dm:298` `loc = null; loc = T` | "Move to top" verb, restacking | A render-order API; no nullspace | theirs |
| 20 | `datums/gear/loadout_shoes.dm:332` | Self-removal before `QDEL_IN` | `qdel(src)` directly after spilling through the ledger | theirs |
| 21 | `datums/components/overlay_lighting.dm:219` | Parks the directional cone atom | **No anchor**: a render-only atom. Smallest fix: an `/obj/effect/abstract` `NULLSPACE_NATIVE` allowlist, or hold it in `vis_contents` only | theirs |
| 22 | `_helpers/unsorted.dm:1197` `GLOB.dview_mob.loc = null` | The global `view()` helper mob | Same as #21 (abstract, allowlisted) | theirs |
| 23 | `modules/admin/admin.dm:822`, `paperwork/faxmachine.dm:433` `rcvdcopy.loc = null` | Admin fax copy kept in a global list | Keep it as the paper's serialized state (L1) in the fax archive, or in a `fax_archive` slot on the receiving machine | theirs |
| 24 | `xenoarcheaology/finds/Weapons/archeo_guns.dm:21`, `finds/special.dm:87,223`, `effects/vampire.dm:75` | Things "vanishing" | `qdel` | theirs |
| 25 | `game/turfs/simulated/floor_types.dm:16` `/obj/landed_holder` | A data holder for shuttle landing with no position | It should be a datum. **No anchor** until then | theirs |
| 26 | `game/objects/structures/droppod.dm:33` | Pod "falling" off-map during the animation | Keep the pod on the target turf with invisibility, or use an animation effect | theirs |
| 27 | `modules/overmap/sectors.dm:66` | The overmap sector object as an identity anchor ("does not occupy a navigation grid", `sectors.dm:64-65`) | It should be a datum. **No anchor** | theirs |
| 28 | `modules/turbolift/turbolift_map.dm:36` | Map helper removing itself | `qdel` | theirs |
| 29 | `game/machinery/machinery.dm:406,482`; `frame_construction.dm:367,370,387,400` | Parts and circuit boards kept in `component_parts` but placed nowhere | `move_into(machine, SLOT_ID_INTERNALS)` (C6) | theirs |
| 30 | `modules/projectiles/targeting/targeting_overlay.dm:26,227` | The aiming overlay object lives nowhere | A datum plus an image. **No anchor** needed after that | theirs |
| 31 | `projectiles/projectile/bullets.dm:376,428` cap projectiles | Cap guns "fire" nothing | `qdel` | theirs |
| 32 | `game/objects/items/weapons/explosives.dm:70` | Planted explosive hidden while it shows as an overlay on its target | `move_into(target, SLOT_ID_ATTACHED)` (an external slot) | theirs |
| 33 | `game/objects/effects/alien/aliens.dm:60` | Overlay update ordering | Fix the overlay code; `qdel` | theirs |
| 34 | `game/gamemodes/technomancer/spells/apportation.dm:44,61` | Spell item consumed | `qdel` | theirs |
| 35 | `game/objects/effects/particle_holder.dm:28`, `shared_particle_holder.dm:22` | Particle emitters that must not be in containers' contents (`particle_holder.dm:26`) | **No anchor**: render-only. `NULLSPACE_NATIVE` abstract allowlist | theirs |
| 36 | `modules/recycling/disposal_machines.dm:52`, `shieldgen/shield_gen.dm:276` | Commented-out code | Delete the comments | theirs |
| 37 | `unit_tests/dq_predicate_tests.dm:45`, `dq_actor_adapter_tests.dm:118` | Test fixtures | Use `run_loc_floor_bottom_left` or a test holder | theirs |
| 38 | `core/image/Transform.dm:5`, `clothing/head/pilot_helmet.dm:169`, `looking_glass/lg_imageholder.dm:62`, `overmap/overmap_object.dm:64`, `technomancer/spells/mark_recall.dm:29` | `/image` loc clears | Not atoms. Exempt from the lint (the lint matches `/atom/movable` receivers) | theirs |
| 39 | `unit_tests/vore_tests.dm:1` | A false positive (`turf/loc = null` parameter default) | None | — |

**B. Atoms created in nullspace (`new X(null)`)**

| Site | Why | Replacement | Owner |
|---|---|---|---|
| `controllers/subsystems/communications.dm:73` `GLOB.autospeaker = new /mob/living/silicon/ai/announcer(null, ...)`; type at `silicon/ai/ai.dm:1022-1044`; used by `radio.dm:308-329` `autosay()` | The radio code needs a mob as a speaker. A whole AI mob is kept in nullspace, removed from the mob lists every Life (`ai.dm:1037-1044`), and special-cased in `ai.dm:343` | **Not a mob.** A `/datum/speaker` interface (name, voice, languages, `get_hear_source()`) that radio broadcast accepts in place of `mob/M` for `autosay`. The announcer becomes `GLOB.announcer_speaker = new /datum/speaker/announcer`. Delete `/mob/living/silicon/ai/announcer`, its life system and the `ai.dm:343` branch. **Joint:** radio broadcast is theirs, and the announcer mob is ours | joint |
| `_global_vars/__unsorted.dm:64` `GLOB.global_announcer = new /obj/item/radio/intercom/omni(null)` | Global "radio" that `autosay`s | With a datum speaker, `autosay` becomes a proc on the radio network (`/datum/radio_frequency`), and the omni intercom goes. Until then, anchor it on the CentCom z at a landmark | theirs |
| `game/objects/items/weapons/implants/implant.dm:541,554,561`, `nifsoft/software/05_health.dm:53,138,148`, `mob/living/silicon/pai/death.dm:5` `new /obj/item/radio/headset/heads/captain(null)` | Make a throwaway headset to `autosay` a death alarm | `GLOB.announcer_speaker.autosay(...)` on the channel. No atom | **ours** |
| `_helpers/global_lists.dm:115` preview mannequins | Character-preview dummies | **No anchor**: they are appearance generators. Smallest fix: `NULLSPACE_NATIVE` on `/mob/living/carbon/human/dummy/mannequin`, and mannequins must never enter Life or the mob lists (they don't today). Longer term, preview from a prefs-built `mutable_appearance` | **ours** |
| `modules/admin/modify_robot.dm:200-204` | Admin builds a robot to copy modules from | Build it in the admin's holding pen (CentCom) or copy from type data | **ours** (robots) |
| `admin.dm:776`, `topic.dm:1188` admin paper; `inducer.dm:123`; `shuttle_specops.dm:23`, `specops_shuttle.dm:27,102`; `flight_controller.dm:35`; `persistence/storage/smartfridge.dm:109`; `unit_tests/dq_stock_tests.dm:193`; `effects/shared_particle_holder.dm:45` | Various | Make them directly in their destination (smartfridge: stock latent; fax: archive slot), or they become datums | theirs |

**C. `!loc` and `isnull(loc)` guards that exist because of nullspace**

| Site | After elimination | Owner |
|---|---|---|
| `mob/living/life/living_systems.dm:150` placed gate (`if(!self.loc)` blocks the living segment) | Becomes `ASSERT(self.loc)` in test builds and a logged skip in production (it can only be true for a mob mid-deletion, and `life_hibernate` already refuses `QDELETED`). `__defines/life_systems.dm:51` and the comment at `living_systems.dm:142` are updated | **ours** |
| `mob/mob.dm:298,310` (perspective reset "Nullspace during respawn") | Respawn never passes through nullspace after #7 and #8, so the guards go | **ours** |
| `mob/dead/observer/observer.dm:159` | Goes after #7 | **ours** |
| `unit_tests/dq_life_scheduler_tests.dm:22` (the test helper places the mob) | Stays: it places test mobs | ours (test) |
| `game/atoms_movable.dm:133,261` | The mover's own logic. It stays (deletion still uses nullspace) | theirs |
| `game/machinery/doors/checkForMultipleDoors.dm:2,10`, `camera/tracking.dm:49`, `effects/misc.dm:121`, `effects/chem/water.dm:22`, `effects/particle_holder.dm:19`, `clothing/spacesuits/breaches.dm:81`, `xenoarcheaology/finds/find_spawning.dm:14`, `vore/smoleworld/smoleworld.dm:165,219,260`, `overmap/ships/landable.dm:103,106`, `recycling/disposal_machines.dm:383`, `power/tesla/energy_ball.dm:120,156`, `power/singularity/act.dm:73`, `projectiles/projectile.dm:213,286` | Mostly Initialize-order or deleted-object guards. Each is reviewed when its owner converts the site above it; most become `QDELETED(src)` checks | theirs (smoleworld is vore: **ours**, but its guards are for `Initialize` before placement, so they stay) |

**D. Our remaining "stored somewhere" cases** (not nullspace today, but they need the same rule,
so the design names their anchor):
- **Protean bodies.** The humanoid form is already inside the rig (`protean_form.dm:68`,
  `H.forceMove(rig)`). That move becomes `H.move_into(rig, SLOT_ID_RIG_OCCUPANT)` (sealed,
  reaches_mobs, clock speed from the rig's state). The blob form's core, the orchestrator
  organ, stays inside the protean's body tree (framework 2). The reconstitutor
  (`protean_reconstitutor.dm:331`) moves the brain `move_into(src, SLOT_ID_RECON_CORE)`.
- **Soulcatcher and VR.** A caught mind's brainmob (`vore/eating/soulcatcher.dm`,
  `nifsoft/software/13_soulcatcher.dm`) lives in the soulcatcher's NIF or gem through a
  mind-host slot (2.6). A VR occupant's real body stays in the VR pod's occupant slot (C8a
  already declares one), and its avatar's cleanup timer (`avatar.dm:125`) is world clock.
- **Possession and teleop** (`body_backup.teleop`, `vorepanel.dm:1251`): the backup body lives
  in the possessing object's occupant slot, as in #5 and #6.

### 3.3 File layout and slices

| Slice | Owns | Items |
|---|---|---|
| N1 mobs | `mob/inventory.dm` (#4), `mob/dead/observer/observer.dm` (#5 ghost side, #7, C), `mob/new_player/{login.dm,lobby_browser.dm}` (#8, #9), `mob/mob.dm` (C), `mob/mob_grab_specials.dm` (#12), `mob/living/living.dm` (#16), `mob/living/life/living_systems.dm` (placed gate) | — |
| N2 medical equipment | `game/objects/items/{robobag.dm,bodybag.dm}` (#14, #15), `mob/living/carbon/brain/MMI.dm` (#6 MMI side, #10) | Needs the J4 slot declarations on these holders (ours to declare) |
| N3 vore and resleeving | `vore/eating/{belly_obj.dm,belly_slot.dm,vorepanel.dm,soulcatcher.dm}`, `nifsoft/software/13_soulcatcher.dm`, `resleeving/*` | #5 belly side, D |
| N4 proteans | `species/station/protean/*`, `game/machinery/protean_reconstitutor.dm` | #11, D |
| N5 speakers (joint) | Ours: `silicon/ai/ai.dm` (announcer), `implants/implant.dm`, `nifsoft/software/05_health.dm`, `silicon/pai/death.dm`, `communications.dm:73`. Theirs: `radio.dm`, `__unsorted.dm:64` | B |
| N6 (other session) | Every "theirs" row, plus the lint | A, B, C |

N1 to N4 need framework 2's O2 (slots) for the backup and occupant slots. They can land in the
same wave, after O2.

### 3.4 Tests

- `dq_nullspace_audit` (test-build only): after the full unit suite, count
  `/atom/movable` instances with `loc == null` that are not `QDELETED` and not
  `NULLSPACE_NATIVE`. The count must be 0. This is the runtime counterpart of the lint.
- Digestion with reform: a digested prey's backup body is in the belly's backup slot; deleting
  the ghost leaves it there; deleting the predator deletes it (DELETE policy) without a hard
  delete; reforming moves it out to the belly's turf.
- The announcer speaks on a channel without any `/mob/living/silicon/ai/announcer` existing.
- Death alarm implants `autosay` without creating a headset.

### 3.5 Lint (theirs to host; we supply our allowlist)

`tools/ci/check_nullspace.py`:
- `moveToNullspace(` or `nullspace_for_deletion(` anywhere outside `atoms_movable.dm` is an
  error.
- `\.loc\s*=\s*null` and `\bloc\s*=\s*null` on a movable receiver are errors. `/image`
  receivers are recognised by declared type or name and exempted.
- `forceMove(null)` is an error.
- `new /(obj|mob)[^(]*\(\s*null` is an error, except for types flagged `NULLSPACE_NATIVE`
  (declared in `code/__defines/nullspace_native.dm`: `/mob/new_player`, the mannequin, and the
  abstract render effects #21, #22, #35).
- An allowlist ratchet for "theirs" rows until N6 finishes.

---

## 4. The exposure (pharmacology) model

### 4.1 Today, and the bugs

- **Three holders on carbons.** `touching` (`carbon_defines.dm:19`, `carbon.dm:6`),
  `ingested` and `bloodstr` (`bloodstr` is `reagents`) are metabolised each Life in that order
  (`human/life.dm:1253-1259`) through `on_mob_life()` (`_reagents.dm:82-196`). That one proc
  holds the gates, the organ-dependent rates, the route switch, the overdose check and the
  removal.
- **Treatment and factors come from volumes.** The body builds a treatment snapshot from total
  volume across holders (`body.dm:280-334`) and scales it with
  `dq_chem_dose_scale(volume)` (`affliction.dm:514-517`). Factors do the same
  (`factors.dm:290-304`). Those paths bypass every gate that `on_mob_life()` applies.
- **Effects are code.** There are 179 `affect_blood`, 82 `affect_ingest`, 29 `overdose`, 22
  `affect_touch`, 16 `touch_mob`, 15 `touch_obj`, 22 `touch_turf`, 10 `mix_data`, 6
  `initialize_data`, 5 `on_mob_life`, 2 `on_mob_end_metabolize` and 1 `on_mob_metabolize`
  override, 395 in total across 18 files. Inside
  `code/modules/reagents/reagents/*.dm` they make: 134 `injure(` calls, 52 `mend(` calls, 59
  `bodytemperature` writes, 69 stun/weaken/paralyse/sleep calls, about 200 status-counter
  writes (jitter, dizzy, drowsy, druggy, hallucination, confusion, blur, slur, stutter), 36
  nutrition writes, 15 radiation writes, 104 `to_chat`, 50 `emote`, 204 `prob(`, 289
  species/alien branches and 36 `isSynthetic()` checks. There are about 707 reagent type
  definitions: `food_drinks.dm` 446, `medicine.dm` 77, `other.dm` 62, `toxins.dm` 43,
  `dispenser.dm` 27, `vore.dm` 14, `virology.dm` 10, `drugs.dm` 9, and the rest in small files.

**The audit's reagent bugs:**

| # | Bug | Where | Cause |
|---|---|---|---|
| R1 | Topicals never heal | `body.dm:316-326` | `collect_reagent_volumes()` counts `bloodstr` and `ingested` but not `touching`, so bicaridaze (`treatment.dm:42-43`, `medicine.dm:77-91`) and dermalaze (`treatment.dm:170-172`) provide no treatment while on the skin. Only the fraction that `dermal_absorption` moves into blood acts, and bicaridaze has `dermal_absorption = 0` |
| R2 | Healing ignores allergy, biology, dead and species gates | `body.dm:292-308`, `factors.dm:295-304`, `affliction.dm:275-285` vs `_reagents.dm:85-88,179-181` | The medical-allergy gate, `affects_robots`/`isSynthetic`, and `affects_dead` apply only inside `on_mob_life()`. Treatment tags, factors and `cured_by` read raw volume, so an allergic patient is still healed, and a synth is healed by organic drugs |
| R3 | `overdose_mod` compounds | `_reagents.dm:214` | `overdose_mod *= H.species.chemOD_mod` writes the reagent instance's var on every overdosing tick: exponential growth (or decay) with time in overdose |
| R4 | `species_factors` replace instead of layering | `factors.dm:345-350` | A species entry replaces the whole `factors` table. For example, the slime entry at `medicine.dm:507` drops every base factor of that drug except the three it lists. `IS_DIONA = null` is the intended "nothing" and stays expressible |
| R5 | Blood relabelled in `take_blood` | `organs/blood.dm:259-288` | It finds any blood already in the container and overwrites its `donor`, `blood_DNA`, `blood_type` and colour with the new donor's, for the whole volume. Mixing two donors makes all of it the second donor's |
| R6 | Direct heals through legacy procs | `medicine.dm:69-75` (`dq_reagent_close_wounds` → `W.heal_damage`), `:780,785,801` | They bypass `mend()` and its biology gate, budget and logging (`body.dm:223-252`) |
| R7 | Radiation healed twice | `medicine.dm:1114-1115,1135-1136,2095-2096,2114-2115`; `other.dm:219` | Hyronalin and arithrazine write `M.radiation -=` and `accumulated_rads -=` directly **and** carry `TREAT_ANTIRADIATION` (`treatment.dm:135,138`) against the radiation afflictions. `other.dm:219` zeroes radiation outright |
| R8 | Direct `bodytemperature` writes | 59 sites, for example `medicine.dm:1370-1372`, `food_drinks.dm:803-882,1070-1072,1457-1467,1717-1727,2608-2618,3203,3329`, `dispenser.dm:178-180,224-226`, `other.dm:224-226`, `modifiers.dm:44`, `toxins.dm:447` | They bypass H2's setter and the thermo strategies, and the H2 lint will reject them (`roadmap.md` guardrail "No direct `bodytemperature` writes") |
| R9 | Doses unscaled | `_reagents.dm:93,172-178`; `affliction.dm:514`; `body.dm:321-322` | Removal is `metabolism` per Life cycle, not per second, so a longer cycle (hibernation wakes, lag, `seconds` > nominal) under-doses, and stasis cycle skipping distorts it further. Dose scale uses **present volume summed across blood and stomach**, so a full stomach counts as a systemic dose before any absorption |

### 4.2 Routes and compartments

```
            absorption k_route→blood                     clearance
 SKIN  ──(dermal_absorption, skin integrity)──┐
 EYES  ──(ocular_absorption)──────────────────┤
 LUNGS ──(inhaled_absorption × ventilation)───┼──► BLOOD ──(k_hepatic × BF_HEPATIC + k_renal × BF_RENAL)──► gone
 STOMACH ─(ingest_absorption × gut function)──┘      │
                                                      └──► local compartments may also act locally (topicals, eye drops)
 RADIATION (pseudo-compartment: dose in Gy)  ──(k_rad_clear × BF_RAD_CLEARANCE)──► gone
```
Each compartment is first-order. With amount `A`, absorption rate `ka` (per second) and
clearance `kc`, the local amount is `A(t) = A0·e^{-(ka+kc_local)·t}`. The absorbed mass moves
into blood, where `B(t)` has the standard two-compartment closed form. Both are exact over any
interval, which satisfies framework 1's split-invariance rule. Compartments therefore **settle
on the body clock**, not per tick:
- `exposure.settle()` runs from the chemicals life system each cycle with
  `ctx.body_seconds`, and on any read (a scanner, `effective_dose()`).
- Thresholds such as an overdose band, an addiction level or a withdrawal onset are body-clock
  events computed from the closed form, so a hibernating patient still overdoses on time.

**Rates are data plus factors:**

| Rate | Reagent data | Body factor (new `BF_*`, `code/__defines/body_factors.dm`) | Organ source |
|---|---|---|---|
| Skin → blood | `dermal_absorption` (exists, `_reagents.dm:65`) | `BF_DERMAL_PERMEABILITY` (burns raise it) | Limb burn wounds |
| Eyes → blood | `ocular_absorption` (new, default 0.1) | — | Eyes organ |
| Lungs → blood | `inhaled_absorption` (new, default 1) | `BF_VENTILATION` (physiology, `body_architecture.md` §10) | Lungs |
| Stomach → blood | `ingest_absorption` (new, derived from today's `ingest_met`) | `BF_GUT_ABSORPTION` (stomach and intestine damage; replaces `_reagents.dm:119-131,146-159`) | Stomach, intestine; machine cycler; protean refactory |
| Blood clearance | `clearance` (derived from today's `metabolism`) | `BF_HEPATIC_CLEARANCE`, `BF_RENAL_CLEARANCE`, `BF_METABOLISM` (exists), cardiac output (replaces `_reagents.dm:110-117,138-145`) | Liver, kidneys, heart or pump |
| Filtering organs | `filtered_organs` (exists, `_reagents.dm:14`) | Folded into the hepatic and renal factors | — |

Organ-dependent rates stop being read in `on_mob_life()`. The organs contribute factors
through their afflictions and presence, which the body already caches (`factors.dm:244`).

**Storage.** `/datum/exposure` is owned by `/datum/body`, lazily. It holds one small store per
compartment:
```dm
/datum/exposure
	var/datum/body/body
	/// ROUTE_* -> /datum/reagents, lazily (null until a reagent arrives by that route).
	/// ROUTE_BLOOD is the mob's existing `reagents` holder, so reagent code that adds to the
	/// bloodstream keeps working.
	var/list/stores
	/// reagent id -> cached effective scale this settle (see 4.3); rebuilt on settle.
	var/list/dose_cache
	var/settled_at     // body clock
	var/list/rad       // radiation pseudo-compartment: list(dose_gy, accumulated_gy)
```
`carbon.touching` and `carbon.ingested` become `exposure.store(ROUTE_SKIN)` and
`exposure.store(ROUTE_STOMACH)`. The accessors keep their names for one wave, as
`/mob/living/carbon/proc/touching()` style procs, then all callers are converted (about 60).
When containment §11 lands (reagents as fluid stores), each store becomes a fluid slot: blood on
the body, stomach on the stomach organ, lungs on the lungs. The J10 request below asks for this.

### 4.3 One `effective_dose()`

```dm
/// The dose `owner` feels of this reagent by `route` (ROUTE_SYSTEMIC for blood-borne action,
/// or a local route for topicals and eye drops), after every gate. `purpose` is DOSE_BENEFIT,
/// DOSE_HARM or DOSE_ANY. Returns a dose scale: 0 = none, 1 = standard dose, up to DQ_CHEM_DOSE_CAP.
/datum/reagent/proc/effective_dose(mob/living/owner, route = ROUTE_SYSTEMIC, purpose = DOSE_ANY)
```
The gates, in order, each a cheap check on data the body already caches:
1. **Presence.** `amount = owner.body.exposure.amount(id, route)`. At 0, return 0.
2. **Biology.** `if(!(reagent_biology & owner.body.biology_of(route_part(route)))) return 0`.
   `reagent_biology` replaces `affects_robots` (`_reagents.dm:26`) and the 36 `isSynthetic()`
   checks: `BIOLOGY_ORGANIC` by default, `| BIOLOGY_SYNTHETIC` where `affects_robots` was set.
   `synth_reag_processing` becomes a synthetic body's factor `BF_SYNTH_CHEM_UPTAKE`.
3. **Dead.** `if(owner.stat == DEAD && !affects_dead && !owner.factor(BF_CIRCULATION_ASSIST)) return 0`.
   `BF_CIRCULATION_ASSIST` is the `bloodpump_corpse` modifier's factor (`_reagents.dm:85`).
4. **Species immunity.** `if(owner.reagent_tag() in immune_species) return 0`. This replaces the
   `species_factors = alist(IS_DIONA = null)` idiom (`medicine.dm:5`, and about 12 more).
5. **Allergy.** If `purpose` includes BENEFIT and the owner has a medical allergy to it, the
   benefit is 0. HARM is unaffected. The allergic reaction itself is an affliction trigger
   (4.5), not a special factor (`factors.dm:360-363` moves).
6. **Species potency.** For BENEFIT: `× species.chem_strength_heal` (the one place it is read).
   For HARM: `× species.chem_strength_tox`. Overdose thresholds are scaled by
   `species.chemOD_threshold` inside the dose curve (4.5), **never written back** (R3).
7. **Interference.** `× body.reagent_cure_modifier(id)` for BENEFIT (`body.dm:274-278`).
8. **Dose band.** `dq_dose_curve(amount, standard_dose, cap)` replaces
   `dq_chem_dose_scale(volume)`. The curve is linear to standard and then saturating (a Hill
   curve with n = 1 above the standard dose) by default, so pushing past standard helps less.
   A reagent can override `dose_curve`.

Every consumer calls it:
- `build_treatment_snapshot()` (`body.dm:280`) loops over reagents present in any
  compartment and uses `effective_dose(owner, route, DOSE_BENEFIT)` for each route where the
  reagent's tags act (`treatment_routes`, default `ROUTE_SYSTEMIC`; topicals use
  `ROUTE_SKIN`, which fixes R1).
- `accumulate_reagent_factors()` (`factors.dm:290`) uses `DOSE_ANY`.
- `apply_treatment()` (`affliction.dm:271`) reads the snapshot and the direct `cured_by`
  pairs through `effective_dose`, not raw volume.
- Scanners and the medical book show `effective_dose` and the gate that zeroed it
  ("no effect: allergy").

**Topicals act locally.** A skin compartment dose treats afflictions located on limbs.
Per-limb skin exposure is not modelled: skin is one compartment, and the topical's treatment
applies to located wound afflictions on any organic limb, scaled by coverage (a
`skin_coverage` fraction set by the applicator, for example a patch on one limb). This is a
deliberate simplification. `/datum/exposure` keeps a `skin_limbs` weighting lazily only when an
applicator targets a limb.

### 4.4 Effects as data

A reagent's effects are declared on its type. The runtime reads them at the effective dose.

```dm
/datum/reagent
	// Benefit
	var/list/treatment_tags          // exists (treatment.dm:32)
	var/treatment_routes = ROUTE_SYSTEMIC
	// Continuous state
	var/alist/factors                // exists (factors.dm:338), scaled by effective_dose(DOSE_ANY)
	/// IS_* -> alist of factor deltas ADDED to `factors` (layering; R4). Replaces species_factors.
	var/alist/species_factor_layers
	var/immune_species = NONE        // IS_* bitfield/list (gate 4)
	var/reagent_biology = BIOLOGY_ORGANIC
	// Harm and other afflictions, by dose curve
	/// list(list(affliction_type, onset_dose, severity_per_excess_dose, route_mask, purpose)), static per type
	var/list/dose_afflictions
	var/overdose                     // exists: becomes a dose_afflictions row (/datum/affliction/overdose/<class>)
	var/datum/addiction_profile/addiction  // path; singleton per path
	// One-off effects
	/// list of /datum/reagent_effect paths with args, compiled once per type into singletons.
	var/list/effects
	// Per-unit metabolic side effects
	var/nutrition_per_unit = 0
	var/hydration_per_unit = 0
	/// Thermal effect: list(target_kelvin, watts_per_dose) through H2's heat API (R8)
	var/list/thermal_effect
	// Clearance and absorption (4.2)
	var/clearance = REAGENT_CLEARANCE_DEFAULT
	var/ingest_absorption = 1
	var/ocular_absorption = 0.1
	var/inhaled_absorption = 1
	var/half_life                    // breakdown in containers (framework 1), null = stable
```

**Afflictions are triggered by dose curves.** `code/modules/body/exposure/dose_triggers.dm`
defines `/datum/affliction_trigger/dose` (the existing trigger type, `body_architecture.md` §6).
On each settle, for each reagent present and each `dose_afflictions` row whose onset is
exceeded, it calls `body.afflict(type, location, severity)` with severity proportional to the
excess × seconds. Below onset, the affliction resolves through its own natural progression.
Overdose, side effects (for example hallucinogen psychosis), allergic reaction
(`/datum/affliction/allergic_reaction`) and chemical burns all use this path, and there is no
bespoke `overdose()` proc.

**Addiction and withdrawal.** `/datum/addiction_profile` holds a gain rate per dose second, a
decay rate per second, a withdrawal affliction type and a threshold. The addiction level is a
body-clocked value on `/datum/exposure` (id → level), so it decays at a rate
(`withdrawl.dm:7-8`'s `prob(8)` per tick becomes an exact rate). Crossing the threshold with no
dose afflicts `/datum/affliction/withdrawal/<class>`. The stages, messages, emotes and vomiting
of `withdrawl.dm:10-55` become that affliction's stages and symptoms (the symptom library,
`medical/symptoms/`). BF_STABILIZATION's suppression (`withdrawl.dm:14`) becomes a
`treated_by` tag on the withdrawal affliction. `handle_addiction()` is deleted.

**One-off effects are small named datums.** `code/modules/body/exposure/effects/*.dm`:
```dm
/datum/reagent_effect                       // singleton per (path, args) through dq_reagent_effect()
	var/route_mask = ROUTE_ANY
	var/min_dose = 0
/datum/reagent_effect/proc/apply(mob/living/owner, datum/reagent/R, dose, seconds)
```
The starter set was chosen by the pattern counts in 4.1:
`/emote` (name, chance per minute), `/message` (text, chance per minute, span),
`/status` (counter id, amount per second; for jitter, dizzy, drowsy and the other ~200
writes), `/incapacitate` (stun, weaken, paralyse or sleep; per-minute chance and duration; 69
sites), `/ignite` (fire stacks; 12 sites), `/nutrition` (handled by the per-unit vars, not a
datum), `/radiate` (adds to the radiation pseudo-compartment; `toxins.dm:1124`),
`/transform` (species or mob transform; bespoke), `/spawn` (spiderlings `other.dm:955`, larvae
`other.dm:1130`; bespoke), `/purge` (removes other reagents from a compartment; charcoal-like),
and `/mend_burst` (one-shot `mend(tag, amount)`; replaces R6's `dq_reagent_close_wounds`).
Chance per minute is converted through `PROB_OVER`, so seconds scaling (R9) is built in.

**What stays code.** Reagents whose effect is a mechanic rather than a physiological response
keep a proc: `touch_obj`, `touch_turf` (cleaning, melting, lube), `mix_data` and
`initialize_data` (data merging), and container reactions. These are not mob exposure.
`touch_mob` (clothing contact) becomes "adds to ROUTE_SKIN × (1 − clothing coverage)", which is
data.

### 4.5 Unification: breath and radiation

- **Toxic gases produce doses.** The breathing system's toxic branches
  (`human/life.dm:766-816`: phoron → `REAGENT_ID_TOXIN` into `reagents` at `:775`; N2O →
  paralyse and sleep at `:802-810`; methane → quality) become one breath step: for each gas in
  the species' **breath profile** with an exposure mapping
  (`gas_id → list(reagent_id, units_per_mole)`), add to `ROUTE_LUNGS`. N2O maps to a `nitrous`
  reagent whose effects are `/incapacitate` data. Phoron maps to `phoron_inhaled` with its dose
  afflictions. The pressure thresholds (`safe_toxins_max`) become the reagent's onset dose, so
  thin exposure is dosed proportionally instead of all-or-nothing. The breath profile work
  (wave G) moves `poison_type`/`exhale_type` (`species.dm:155-156`) into
  `/datum/breath_profile`. This framework defines only the gas → reagent hook it uses:
  `/datum/breath_profile/proc/exposures(datum/gas_mixture/breath) -> list(reagent_id, units)`.
- **Radiation produces dose.** Radiation from the M5 propagation (theirs) calls
  `owner.body.exposure.irradiate(gray)`. The pseudo-compartment holds the current dose
  (clearing at `k_rad_clear × BF_RAD_CLEARANCE`) and the accumulated dose (clearing much more
  slowly). The radiation life system (`human/life.dm:363-409`) becomes dose-curve afflictions
  (`/datum/affliction/radiation_sickness`, `radiation_burns`, `/datum/affliction/lesion/...`)
  plus `species.radiation_mod`/`rad_removal_mod` as factors. Antiradiation drugs raise
  `BF_RAD_CLEARANCE` through their factors and keep their `TREAT_ANTIRADIATION` tag for the
  radiation afflictions. They no longer write `radiation` (R7), so the healing counts once:
  either through clearance of the dose, or through treatment of the afflictions, and the design
  assigns them as clearance (dose) plus tag (existing damage). These are different things, so
  there is no double effect on the same quantity. `TRAIT_HALT_RADIATION_EFFECTS`
  (`life.dm:379`) becomes an `immune` gate on those afflictions.

### 4.6 How the model removes each bug

| Bug | Removed by |
|---|---|
| R1 topicals | `treatment_routes = ROUTE_SKIN` on the topicals; the skin compartment's effective dose feeds the snapshot (4.3). Regression test: bicaridaze on skin closes cuts with no blood level |
| R2 gates | Every consumer goes through `effective_dose()`; no reader touches raw volume (lint). Tests: an allergic human gets 0 benefit and the allergy affliction; a synth gets 0 from an organic drug; a corpse gets 0 unless the circulation assist is on |
| R3 `overdose_mod` | Overdose is a `dose_afflictions` row. The species modifier is read in the dose curve and never written. The `overdose_mod` var is deleted. Test: 10 minutes of overdose gives the same severity rate in minute 10 as in minute 1 |
| R4 species factors | `species_factor_layers` add to `factors`; `immune_species` handles "nothing". Test: a slime on the `medicine.dm:507` drug has the base factors plus the layer |
| R5 blood relabelling | Blood becomes a **keyed-data reagent**: a holder keeps separate entries for blood with different `donor_key` (hash of DNA, type and species). `take_blood()` adds a new entry or merges into the same donor's entry, never relabels. Transfusion (`organs/blood.dm`) picks entries per donor and checks compatibility per entry. Requires the holder change J10(c). Test: two donors in one bag stay two donors; transfusing the mix causes a reaction only if either is incompatible |
| R6 legacy heals | `/datum/reagent_effect/mend_burst` → `mend()`. Lint: no `heal_damage(`, `heal_wound` or `rejuvenate(` in `code/modules/reagents/**` |
| R7 radiation | 4.5. Lint: no `radiation` or `accumulated_rads` writes outside `exposure/radiation.dm` |
| R8 temperature | `thermal_effect` data goes through H2's heat API: `owner.body_heat_add(watts)` or `owner.body_heat_toward(target, watts)` (J11). Lint (shared with H2): no `bodytemperature` writes in `code/modules/reagents/**` |
| R9 unscaled doses | Everything settles in body seconds with closed forms. Dose scale reads the compartment for the route, never the sum of stomach and blood. Test: identical final blood curves for Life periods of 1 s, 2 s and 4 s, and under stasis 0.5 against real time × 0.5 |

### 4.7 Migration of about 395 overrides (707 type definitions)

**Phase A: the engine, no reagent changes.** X1 and X2 build the exposure stores,
`effective_dose()`, the dose triggers, the effect datums and an **adapter**: while a reagent
still has an `affect_*` override, the chemicals system calls it with
`removed = amount absorbed/cleared this settle` and `alien = reagent_tag`, exactly as
`on_mob_life()` did, but gated by `effective_dose() > 0`. The adapter is migration scaffolding
that exists **only on the working branch**. The user has decided that W3 and W4 merge to
`master` together, so `master` never contains the adapter (AGENTS.md "no shims").

**Phase B: an automated codemod,** `tools/dq_reagent_codemod/` (Python). It parses each
`/datum/reagent/<path>/affect_(blood|ingest|touch)` and `overdose` body and classifies each
statement by pattern:

| Pattern | Regex anchor | Emits | Est. share |
|---|---|---|---|
| Toxin harm | `M.injure\(INJURY_TOXIN, ([\d.]+) \* removed` | `dose_afflictions += /datum/affliction/toxicity` with rate k | ~40% of `injure(` |
| Other injure | `injure\(INJURY_(\w+), ([\d.]+) \* removed` | `dose_afflictions` row, per kind (burns → chemical burn) | the rest |
| mend | `M.mend\(TREAT_(\w+), ...removed` | `treatment_tags` entry, or `/mend_burst` for bursts | 52 |
| Nutrition | `adjust_nutrition\(([\d.]+) \* removed\)` / `nutrition \+=` | `nutrition_per_unit` | 36 |
| Status counters | `M\.(make_jittery\|make_dizzy\|drowsyness\|druggy\|...)` | `/status` effect | ~200 |
| Incapacitation | `M\.(Weaken\|Stun\|Paralyse\|Sleeping)\((\d+)\)` under `prob(p)` | `/incapacitate` with p per cycle → per minute | 69 |
| Chat and emote under `prob` | `if\(prob\((\d+)\)\)\s*to_chat\|emote` | `/message`, `/emote` | 104 + 50 |
| Temperature | `bodytemperature` | `thermal_effect` | 59 |
| Species branches | `if\(alien == IS_(\w+)\)` / `alien != IS_DIONA` | `immune_species` or `species_factor_layers` | 289 |
| Synthetic branches | `isSynthetic\(\)` | `reagent_biology` | 36 |
| Dose-gated blocks | `if\(dose > (\d+)\)` / `volume > ` | `min_dose` on the effect or a `dose_afflictions` onset | 272 `dose` refs |
| Residue | Anything else | Left as a named effect datum stub for a human | — |

The codemod rewrites the file in place, one reagent per commit hunk. It emits a report of
residue per reagent. Output passes `tools/build/build.sh lint`, and a generated parity test (X6)
runs each converted reagent at three doses on a test human for 60 body seconds against a
recorded baseline from the pre-migration tree (injury load per category, factor values,
counters, nutrition). A tolerance of 10% is allowed, because the old per-tick `prob()` noise
becomes expectation-exact.

**Phase C: conversion order** (by file; each file is one slice, disjoint):
1. `medicine.dm` (77 types, 93 overrides). Medical priority: it fixes R1, R2, R6 and R7.
2. `toxins.dm` (43 types, 53 overrides) and `toxin.dm`.
3. `core.dm` (blood, water, fuel; 17 overrides). Includes R5 (blood keyed data) with
   `organs/blood.dm`.
4. `dispenser.dm` (ethanol and the base elements; 23) and `drugs.dm` (9), with the addiction
   profiles and `withdrawl.dm`.
5. `other.dm` (62 types, 42 overrides; the residue-heavy one: spiders, transforms).
6. `food_drinks.dm` (446 types, 100 overrides). The bulk is mechanical: nutrition,
   temperature, messages. It is split into four slices by line range (drinks, alcohol, food
   reagents, the rest) because of its size (6,780 lines).
7. `vore.dm` (15), `virology.dm` (2), `modifiers.dm`, `modapply.dm`, `medicalmods.dm`.
8. Out-of-folder overrides: `contracts/medical_trial.dm` (7), `changeling/.../epinephrine_overdose.dm`,
   `lleill_items.dm` (3), `station_special_abilities.dm` (3), `xeyakin.dm`, `synx.dm` (6).
9. Delete `on_mob_life()`, `affect_*`, `overdose()`, `handle_addiction()`, the adapter,
   `/datum/reagents/metabolism` and `Chemistry-Metabolism.dm`.

### 4.8 File layout

```
code/__defines/exposure.dm                     ROUTE_*, DOSE_*, REAGENT_CLEARANCE_DEFAULT
code/modules/body/exposure/exposure.dm         /datum/exposure, stores, settle(), closed forms
code/modules/body/exposure/effective_dose.dm   effective_dose(), dq_dose_curve()
code/modules/body/exposure/dose_triggers.dm    dose affliction triggers
code/modules/body/exposure/addiction.dm        /datum/addiction_profile, withdrawal afflictions
code/modules/body/exposure/radiation.dm        radiation pseudo-compartment
code/modules/body/exposure/breath_hook.dm      breath_profile exposures() hook (implemented in wave G)
code/modules/body/exposure/effects/*.dm        /datum/reagent_effect family
code/modules/body/exposure/adapter.dm          phase A adapter (deleted in step 9)
code/modules/medical/conditions/pharmacology/  overdose, toxicity, allergic_reaction, withdrawal afflictions (existing folder)
tools/dq_reagent_codemod/                      codemod + parity baseline recorder
code/modules/unit_tests/dq_exposure_tests.dm
code/modules/unit_tests/dq_reagent_parity_tests.dm (generated)
```

### 4.9 Slices

| Slice | Owns |
|---|---|
| X1 engine | `__defines/exposure.dm`, `body/exposure/{exposure,effective_dose,adapter}.dm`, `body/body.dm` (snapshot), `body/factors.dm` (reagent part), `body/affliction.dm` (`apply_treatment`, dose scale), `mob/living/carbon/{carbon.dm,carbon_defines.dm}`, `mob/living/carbon/human/life.dm` (chemicals system), `reagents/Chemistry-Metabolism.dm`, `reagents/reagents/_reagents.dm`, `unit_tests/dq_exposure_tests.dm` |
| X2 afflictions and effects | `body/exposure/{dose_triggers,addiction,effects/*}.dm`, `medical/conditions/pharmacology/*`, `reagents/reagents/withdrawl.dm` |
| X3 radiation | `body/exposure/radiation.dm`, the human and alien radiation systems (`human/life.dm:360-409` region only, coordinated with X1 by line region; or X1 lands first), `mob/living/carbon/alien/life.dm` |
| X4 codemod | `tools/dq_reagent_codemod/`, `unit_tests/dq_reagent_parity_tests.dm` |
| X5.n per file | One slice per file or range in 4.7 step order |
| X6 UI | `medical/book/reagents_tab.dm`, `medical/bodyscanner/*`, `tgui` medical interfaces (dose and gate display) |

### 4.10 Tests

- `dq_exposure_tests.dm`: closed-form split invariance per route; absorption ordering (skin
  slower than blood); hepatic failure raises the half-life; stasis 0.5 halves the real-time
  rate; the nine bug regressions (4.6).
- Generated parity tests (X4) per converted reagent.
- A gate matrix: {allergic, synth, dead, diona, normal} × {benefit tag, harm row, factor}
  → expected zero or non-zero.

### 4.11 Lints

- No `volume` reads of `reagent_list` entries in `code/modules/body/**` and
  `code/modules/medical/**` except in `exposure/*.dm`. Everything reads `effective_dose`.
- No `affect_blood(`, `affect_ingest(`, `affect_touch(`, `overdose(` or `on_mob_life(`
  definitions, as a ratchet down to 0 by step 9.
- No `bodytemperature`, `radiation`, `accumulated_rads`, `nutrition` direct writes in
  `code/modules/reagents/**`.
- No `species_factors` identifier (renamed).
- No `prob(` in `/datum/reagent_effect/*/apply` without `PROB_OVER`.

---

## 5. What we need from the other session (joint work list)

These are exact requests. The ID is what our slices cite as a dependency.

| ID | Request | Their files | Needed by |
|---|---|---|---|
| **J1** | **Pre-destroy phase** in `qdel()`, as specified in 2.4. The per-type flag lives on `/datum/qdel_item` (`SSgarbage.items[type].has_pre_destroy`), and `DF_PRE_DESTROYING` is the only instance bit. Adds `COMSIG_PRE_QDELETING`, `/datum/proc/pre_destroy(force)`, and `/atom/movable/pre_destroy()` → `ledger_release_contents(force)`, which drops real contents **and latent entries**. `pre_destroy` never sets `gc_destroyed`. Refuse inserts and `latent_add()` into a pre-destroying holder. `ledger.sync()` skips `DF_PRE_DESTROYING` holders (or every release is a real move out). Delete the `QDELETED` bypass at `api.dm:178-192`. A thing in a slot leaves its holder's slot through the hooks as step one of its own PRE phase. Boot check: slot holders never return `LETMELIVE`. Move the call from `atoms_movable.dm:93-94`. `obj_defense.dm:96` (`deconstruct`, not `Destroy`) stays where it is. `smartfridge.dm:69` is deleted after J1. Test: `qdel(src)` inside `pre_destroy` completes. Audit: every holder `Destroy()` that reads contents (mech `go_out`, `component_parts`) | `garbage.dm`, `containment/{api,ledger,latent}.dm`, `atoms_movable.dm`, `smartfridge.dm`, `__defines/qdel.dm` | O2, O4, N1-N4, K1 (cancel in PRE) |
| **J2** | **Flags plus a FORCED path in `slot_remove()`**: `slot_remove(thing, dest, actor, flags)`. `LEDGER_MOVE_FORCED` skips refusals and pre-signals; the commit bookkeeping (already reached through `doMove`, `atoms_movable.dm:366-369`) is unchanged. `ledger_release_contents()` uses it for SPILL and TRANSFER | `containment/api.dm` | O2 |
| **J3** | **CUSTOM now, HOLDER removed last.** Add `SLOT_DROP_CUSTOM` and `drop_custom(holder, thing, drop)`, run in the PRE phase. Body slots → DELETE (ours, `body/slots.dm:42`). Mech equipment and cargo (`mecha.dm:281,289`) → CUSTOM; only the spill and detach loops leave `Destroy()`, and `go_out` stays. Machine internals (`stock.dm:19`) convert inside their C6. The `SLOT_DROP_HOLDER` define is removed last, with a lint | `containment/*`, `mecha.dm`, `stock.dm` | O2, O4 |
| **J4** | **Keyed slots.** `/datum/slot_def/var/keyed`. The key (`thing.slot_key()`; a part returns `organ_tag`) is **stored on the ledger entry at insert**. `ledger_rekey(thing)` is called when a key changes. The index is a lazy `keys[slot_id]` assoc, looked up with `holder.slot_lookup(slot_id, key)` in O(1). A duplicate key is refused through the normal refusal path, with a reason. `verify()` recomputes the index | `containment/{slot_def,ledger,api}.dm` | O2 |
| **J5** | **One ledger move hook**, shared by our clocks and their C10. The gate is **one var test on the moving thing**: `src.move_hooks`, a tmp bitfield holding its own bits (`MOVE_HOOK_CLOCK` ours, `MOVE_HOOK_LATENCY` theirs) plus `MOVE_HOOK_SUBTREE`, which ledger `propagate()` keeps set on any holder with a hooked descendant. There is no P1 query and no peek per move. In `doMove()`: the before-hook runs **before `loc =`**, and the after-hook runs **right after `note_enter`, before `Exited`/`Uncrossed`**. A thing with `MOVE_HOOK_SUBTREE` walks its hooked descendants, pruning on the same bit. Hooks must not move, qdel or sleep, which a debug assert enforces. They may call `REACT_AT`/`REACT_CANCEL` and clock procs. The nullspace branch (`atoms_movable.dm:427`) is handled too: deletion moves run the before-hook, so clocks settle and cancel. Bench `idle` and `major_events` before and after. C10's `dq_latent_touch` stays unconditional; only its collapse-cancel uses `MOVE_HOOK_LATENCY`. We write the clock handlers; they write the gate, the walk and the latency handlers | `atoms_movable.dm` (`doMove`), `containment/ledger.dm`, `__defines/containment.dm` | K1, K3, their C10 |
| **J6** | **Thing-side commit hooks**: `thing.on_slotted(holder, slot_id, old_holder)` and `thing.on_unslotted(holder, slot_id, new_holder)` after a committed move, gated by a per-type or `move_hooks` bit. They **also fire from `reslot`** (`ledger.dm:221`). Parts implement `on_attached`/`on_detached` through these | `containment/ledger.dm` | O2 |
| **J7** | **`TAG_CLOCKED` as a dynamic tag.** When a thing's clocked status changes, it calls `ledger_refresh_contribution(thing)`. `TAG_MOVE_HOOKED` is dropped in favour of J5's `MOVE_HOOK_SUBTREE` bit | `datums/properties/*`, `containment/ledger.dm` | K1 |
| **J8** | **`slot_item(slot_id)` lands now** (the first entry, or null), with the existing `slot_contents` and J4's `slot_lookup`. No raw `contents` walks in our part code | `containment/api.dm` | O2 |
| **J9** | **Clock providers in their files**: the freezer procs in `crates.dm:319-333`, `boxes.dm:524-538` and `bodybag.dm:216-242`, and the gripper in `robot_simple_items.dm:712-726`. We delete the `preserved` writers and add `clock_speed`; they review. In our W2 | `crates.dm`, `boxes.dm`, `bodybag.dm` | K4 |
| **J10** | **Reagents as fluid stores** (containment §11). (a) `store.transfer(to_store, id, amount, flags)` with a no-reactions flag; (b) lazily created stores keyed per route or organ. (a) and (b) are in W3, with the **API agreed before X1 starts**. (c) keyed-data entries (`REAGENT_KEYED_DATA`, blood, R5) are in W4, behind a flag | `modules/reagents/holder/holder.dm` | X1 (a, b), R5 (c) |
| **J11** | **Heat procs for reagents**: `owner.body_heat_add(watts)` and `owner.body_heat_toward(target_k, watts)`, shipped with a single-setter fallback until H2's body node exists. The `bodytemperature` write lint waits until H2. In W4 | temperature track | X5 (R8) |
| **J12** | **P5 abilities**, on P5's schedule, for cooldown-bearing organ and species powers (`heart_anomalock.dm:75`, `shadekin.dm:186-192`). We provide the ability definitions | rules track | W5 |
| **J13** | **P1 property definitions** for reagent type data (absorption, clearance, biology, immune species) | `datums/properties/*` | X6, W5 |
| **J14** | **Radiation M5** calls `exposure.irradiate(gray)` on mobs instead of writing `radiation`. In W3 | simulation track | X3 |
| **J15** | **Nullspace lint** as a **ratcheted allowlist**, plus `NULLSPACE_NATIVE` and the "theirs" rows in 3.2. `dropInto` (`_atom.dm:448`, 31 callers) keeps its behaviour behind a `stack_trace` until audited. §3.2 #29 folds into C6. In our W2 | various | N6 |
| **J16** | **Radio speaker datum**: radio broadcast accepts a `/datum/speaker` in place of a mob for `autosay` (3.2 B). In our W2 | `radio.dm`, `communications.dm` | N5 |

**Their delivery order:** J2, J4, J6 and `slot_item` (J8) first, on branch
`rewrite/ledger-joint`, then J1, then J7, then J5, then J3. J9, J15 and J16 land in our W2.
J10(a, b) and J14 land in W3. J10(c) and J11 land in W4.

What C1 and C11 already provide: C1 as built (`containment.md` §2.1, `api.dm`) gives the
transaction API, `note_exit`/`note_enter` bookkeeping in `doMove`, `COMSIG_SLOT_*` signals,
`on_slot_changed()` (these fire for spill too, through `doMove`), the drop policies (run
inside base `Destroy`, which is gap 1) and `verify()`. C3 gives body slots, and the interior slot `SLOT_ID_BODY` that currently holds
organs untracked. C8a gives occupant slots (`occupant_slot.dm`). C11 is planned (`roadmap.md`
C11) and has no code on `master`; `slot_item` (J8) lands now on `rewrite/ledger-joint`.

---

## 6. Wave plan

Items in one wave run in parallel; every dependency is in an earlier wave. "J" items are the
other session's; we schedule around them.

| Wave | Ours | Theirs (requests) | Gate |
|---|---|---|---|
| **W1** | **K1** clock core (the move-hook wiring follows J5); **O2** part slots and hooks on `rewrite/ledger-joint` (J2, J4, J6, J8), then against J1; **O5** `return_from_death` (no dependencies) | J2, J4, J6, J8 → J1 → J7 → J5 → J3 | `dq_clock_tests`; `dq_part_lifecycle_tests` for attach and detach; the revive lint on; `idle` and `major_events` benched before and after J5 |
| **W2** | **K2** body time and stasis; **K3** organs on clocks (needs J5); **K4** providers (with J9); **K5** misc timers; **O3a-d** list → query and moves; **O4** destroy and mind (needs J1, J3); **O6** harness, reader codemod, lints; **N1-N4** nullspace (ours); **N5** speakers (with J16) | J9, J15, J16 | Full lifecycle matrix green; stasis parity; `dq_nullspace_audit` = 0 for ours; body_time and part_moves lints on; hard deletes per round not up (bench `major_events`, `idle`) |
| **W3** | **X1** exposure engine and adapter (the adapter is branch-only); **X2** dose afflictions, addiction, effects; **X3** radiation; **X4** codemod and parity recorder. Not merged on its own | J10(a, b) (API agreed before X1), J14 | `dq_exposure_tests`; R1, R2, R3, R4, R7 and R9 regressions |
| **W4** | **X5.1-X5.8** per-file reagent migration; **X6** UI; step 9 deletions; R5 blood with J10(c); R8 with J11. **W3 and W4 merge to `master` together**, so `master` never has the adapter | J10(c) (behind a flag), J11 | Parity suite green; override count 0; adapter gone |
| **W5** | **Grants and capabilities**: organs, implants, traits and equipment grant abilities, languages, verbs and factors through the attach hooks (O2) instead of `organ_verbs`/`handle_organ_mod_special` and `refresh_modular_limb_verbs`; P5 ability definitions for organ powers and cooldowns | J12, J13 | Grant parity tests; no `add_verb` in organ code |
| **W6** | **Traits and genes**: traits as factor sources and grants; genes as heritable trait sets on the body; species built from them | — | — |
| **W7** | **Breath profiles**: `/datum/breath_profile` (required, toxic and exhaled gases, exposures hook from 4.5), replacing `species.breath_type`/`poison_type`/`exhale_type` and the breathing branches in `human/life.dm:660-820` | M1b gas watches (reactor §6 comfort bands) | Breathing parity tests (`dq_atmos_tests.dm:483-487,3327-3356`) |
| **W8** | **Mech body host (C8b)**: `/datum/body` owned by an object through a body host interface (`README.md` coordination table; `body.dm:41`); mech damage through `injure()`. **Occupant behaviour**: sleepers, scanners, cryo, the dogborg sleeper and the mech sleeper as clock providers (stasis speed) plus exposure routes (sleeper injection into ROUTE_BLOOD, cryo cooling via J11) | C8a (done), D3 | C8b "done when" (`roadmap.md`) |

**Critical path:** J2/J4/J6/J8 → J1 → O2 and O4; J7 → J5 → K3; K1 → K2 → X1 → X5 → W5. Clocks (K) and ownership (O)
run in parallel in W1 and W2. Exposure starts after the body clock (K2) because compartments
settle on it. Nullspace (N) rides W2 because its anchors are slots from O2.

**Per-wave rules** (roadmap "Rules for every item"): wholesale conversion, green build, bench
before and after (`tools/build/build.sh bench --runs=3` + `bench-compare`, gates `idle`,
`major_events`, `boot_memory`), lint on, changelog stub, debug logging kept and extended (clock
trace, part attach and detach trace, exposure trace behind `GLOB.exposure_trace`), and this
document updated in the same change when the design moves.
