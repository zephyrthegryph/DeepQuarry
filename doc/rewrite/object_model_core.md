# Object model core API

Status: **authoritative** for the core API. It supersedes the API parts of
[object_model.md](object_model.md) (§7 behaviours, §8 requirements, §9 events,
§10 scheduler, §11 watches, §12 rates, §13 tasks, §16 UI). object_model.md
still owns the concepts: kinds of object, ownership, archetypes, destruction,
Rust interop and dm-health.

Code: `code/datums/om/`, `code/__defines/om.dm`,
`code/controllers/subsystems/behaviours.dm`. Tests:
`code/modules/unit_tests/dq_om_core_tests.dm`,
`code/modules/unit_tests/dq_om_pipeline_tests.dm`. Benchmark:
`code/modules/benchmarks/om_dispatch.dm`. Users: mob Life
([life_on_om.md](life_on_om.md)) and the machines in
`code/game/machinery/machine_pipeline.dm` (rechargers, cell chargers, APCs, SMES).

## 1. What it is for

Game objects stop running code on a timer. They either react to a change they
declared interest in, or run on a cadence the scheduler owns, or wait for a
deadline. Everything is declared in tables, so the framework knows what every
object reads, when it runs and why. Several bug classes are then impossible
by construction (§12).

Three rules hold everywhere:

1. **Declare, don't register.** Behaviours, reactions, derived values,
   effects, checks and tasks are table rows or DEF types. Boot compiles them.
2. **Nothing runs without a change, a cadence slot or a deadline.**
3. **One store per concern.** All statuses, modifiers, grants, clock
   modifiers and suspension holds live in the contribution store. All timers
   live in the deadline wheel.

## 2. Naming

Every framework type lives under `/datum/om/`, because `/datum/event` and
`/datum/effect` already exist (random events, xenoarchaeology). Procs start
with `om_`, except the dt helpers (`approach`, `decay`, `chance_over`,
`move_toward`, `clamp01`), the combinators (`ALL_OF`, `ANY_OF`, `NOT_OF`,
`SUM_OF`, `CHECK`) and `scheduler_advance`. `ALL` was already a
define, hence `ALL_OF`.

| Concept | Path |
|---|---|
| Behaviour | `/datum/om/behaviour/<x>` |
| Pipeline, its stages and frame | `/datum/om/pipeline/<x>`, `/datum/om/stage/<x>`, `/datum/om/frame/<x>` |
| Event | `/datum/om/event/<x>`, `/datum/om/event/before/<x>` |
| Relation | `/datum/om/relation/<x>` |
| Check | `/datum/om/check/<x>` |
| Derived value | `/datum/om/derived/<x>`, or a `DERIVE*()` row |
| Effect | a row in an `effects` table; `/datum/om/effect/<x>` only for custom logic |
| Task | `/datum/om/task/<x>` (a timed action: `/datum/om/task/timed/<x>`), or a row in a `tasks` table |
| Service (global observer) | `/datum/om/service/<x>` |
| Bundle | `/datum/om/bundle/<x>` |
| Entity table | `/datum/om/decl/<x>` with `of = /entity/type` or `of = list(types)` |

Words: an entity **parks** (leaves a ring while nothing is due, `om_park`/`om_unpark`); a
pipeline stage **idles** and **wakes**; statuses keep their game names (stunned, asleep). One
channel vocabulary, `CHANGE_*` (§5), is used by every behaviour and stage.

## 3. Tables first

Most content should need no subclass. An entity type gets a decl, and the
decl lists rows:

```dm
/datum/om/decl/recharger
	of = /obj/machinery/recharger
	include = list(/datum/om/bundle/powered_machine)
	ticks = list(/obj/machinery/recharger/proc/charge = list("every" = 2 SECONDS, "clock" = CLOCK_MACHINE))
	reacts = list(/obj/machinery/recharger/proc/update_icon_state = CHANGE_MACHINE_POWER | CHANGE_MACHINE_CHARGE)
	derived = list(
		DERIVE("can_charge", ALL_OF("machine_usable", /datum/om/check/panel_closed), CHANGE_MACHINE_OUTPUT),
	)
	tasks = list(
		"unwrench" = list("duration" = 2 SECONDS, "claims" = TRUE, "requires" = list(CHECK(/datum/om/check/holding_tool, TOOL_WRENCH), /datum/om/check/adjacent)),
	)

/obj/machinery/recharger/proc/charge(dt)
	// src is the machine, typed. dt is seconds, scaled by the machine clock.
	...
```

DM can't read a type's list vars without an instance, so tables live on
singleton decl datums rather than on the entity type. This is the only
indirection.

| Field (bundle or decl) | Row | Effect |
|---|---|---|
| `of` (decl only) | entity type, or a list of types | rows apply to each and every subtype |
| `include` | bundle types | merged in; bundles nest; cycles are boot errors |
| `ticks` | `/type/proc/x = list(every, clock, lane, max_interval, max_dt, relevance, order_after, requires, step_interval, max_catchup)` | a synthesised behaviour calls `E.x(dt)` |
| `reacts` | `/type/proc/x = CHANGE_mask` | calls `E.x(changes)` once per tick with the union of bits |
| `events` | `/datum/om/event/x = /type/proc/y` | calls `E.y(event)` |
| `behaviours` | full behaviour types (pipelines included) | attached as they are |
| `stages` | stage types | extra pipeline stages for this entity type (§4.10) |
| `derived` | `DERIVE*()` rows | global names, read with `om_derived(E, name)` |
| `effects` | `id = list(combine, stacking, channel, default, expr, type, implies, kind, status fields)` | global effect definitions (§8.1 for statuses) |
| `clocks` | `id = list(min, max)` | global clock domains |
| `checks` | `name = spec` | named check specs, usable anywhere a spec is |
| `tasks` | `name = list(duration, claims, requires, interrupted_by, interrupt_on, on_complete, on_cancel)` | global task names |
| `ui` | `list(list(target = /type/proc/x, watch = mask, stream_rates = list(names)))` | used by `om_ui_bind_table()` |
| `self_effects` | `id = value` | the entity holds these on itself while started |
| `self_grants` | `kind = id or list` | same, for grants |
| `contributes` (relations) | `id = value` | held on the target while linked |
| `source_contributes` (relations) | `id = value` | held on the source (the occupant) |
| `grants_target`, `grants_occupant` | `kind = id or list` | grants, same two directions |

Rules for tables:

- **Base types supply defaults.** A decl for `/obj/machinery` applies to every
  machine. A more specific decl adds rows. Rows are merged, general first.
- **Table values can read the holder.** `FROM_VAR("name")` reads a var of the
  holder (for relation contributions, the item); `FROM_DERIVED(name)` and
  `FROM_EFFECT(id)` read those. Per-instance parameters therefore need no
  subclass. `every` is the exception: it must be a number, because a ring is
  shared by every entity at that interval.
- **Boot parses every row.** An unknown key, a wrong type, an unknown effect
  or relation, a missing mask or an include cycle is a boot error listed in
  `om_registry().errors` and stack-traced. Nothing is checked lazily.
- **Full datums remain the escape hatch** and mix freely with rows: an
  ordered or stateful system is a behaviour type, a complex derived value is
  a `/datum/om/derived` with `compute()`, an effect with custom logic sets
  `type` to a `/datum/om/effect` subtype.
- Atoms whose type has a decl join the object model in `on_materialize()`
  (`om_start()`); other datums call `om_start(E)` themselves.

### 3.1 Combinators and composition

`ALL_OF(...)`, `ANY_OF(...)` and `NOT_OF(x)` combine check specs, effect ids
(for composite effects) and derived-row expressions. They are plain lists
(`list("all", ...)`); they are macros only so they can appear in var
declarations. `SUM_OF(...)` sums effects.

- **Checks** compose from other checks. A composite's `depends_on` is the
  union of its parts. Every spec compiles once to an instance cached by value:
  `CHECK(/datum/om/check/in_range, 1)` and `list(/datum/om/check/in_range = 1)`
  are the same instance.
- **Effects** can be defined from other effects:
  `EFFECT_CAN_MOVE = list("expr" = NOT_OF(ANY_OF(EFFECT_STUNNED, EFFECT_PARALYZED, EFFECT_BUCKLED)), "channel" = CHANGE_MOB_CAN_MOVE)`.
  A composite has no contributions of its own; when a part changes, the
  composite's channel is raised too. Composites of composites are refused.
- **Derived values** can read other derived values (`derived_inputs`, or a
  `FROM_DERIVED` reader). Boot orders them; a cycle is a boot error.
- **Bundles** package any rows (effects, grants, checks, reacts, ticks,
  derived, tasks, ui, relation contributions) and nest with `include`.

### 3.2 Standard library (`library.dm`, `check_library.dm`, `task.dm`)

- **Checks:** `adjacent`, `in_range`, `can_see`, `can_reach`, `holding`,
  `holding_tool`, `hands_free`, `wearing`, `has_client`, `stat_at_most`,
  `conscious`, `alive`, `not_restrained`, `is_type`, `is_living`,
  `target_exists`, `has_effect`, `lacks_effect`, `has_grant`, `var_above`,
  `var_below`, `var_true`, `derived_true`, `powered`, `holder_powered`,
  `not_broken`, `panel_open`, `panel_closed`, `anchored`, `unanchored`,
  `has_access`, `in_slot`, `turf_o2_low`, `on_z`, `same_z`, `in_container`.
  Single-entity checks read `target` when given, else `actor`; actor-side
  checks (holding, wearing, stat, hands) read the actor.
- **Effects:** statuses (`EFFECT_STUNNED`, `EFFECT_PARALYZED`,
  `EFFECT_BUCKLED`, `EFFECT_BLINDED`, `EFFECT_MUTED`, `EFFECT_SLOWED`),
  composites (`EFFECT_CAN_MOVE`, `EFFECT_CAN_ACT`), stat sums
  (`EFFECT_ARMOR_*`, `EFFECT_INSULATION`, `EFFECT_POWER_DRAW`), factors
  (`EFFECT_MOVE_SPEED`), clock multipliers and inhibitions for every clock
  (`EFFECT_CLOCK_<X>_MULT`, `EFFECT_CLOCK_<X>_INHIBIT`), grant kinds
  (`GRANT_ABILITY`, `GRANT_LANGUAGE`, `GRANT_VERB`, `GRANT_ACCESS`,
  `GRANT_TRAIT`).
- **Clocks:** `CLOCK_BIO`, `CLOCK_MACHINE`, `CLOCK_CHEM`.
- **Relations:** `contained_in`, `worn_by`, `buckled_to`
  (gives `EFFECT_BUCKLED`), `pulling`, `grabbing`, `stasis_occupant` (stops
  the occupant's biological clock while the bed is powered), `powered_by`,
  `following`, `host_of`, `claim`. Declared next to their
  feature: `orbiting` (`code/game/orbit.dm`), `leashed_to`/`leash_held_by`
  (`leash.dm`), `tethered_to` (`tethered_item.dm`), `eye_of` (every
  remote eye -> the mob looking through it: AI main and multicam eyes,
  soulcatcher AR/SR projections, the camera MIU) and `active_eye` (mob -> the
  eye it moves with; `take_eye()`/`drop_eye()`, `code/modules/mob/freelook/eye.dm`). A machine's occupant is a
  slot (`/datum/om/relation/slot/occupant`), not a relation of its own.
- **Bundles:** `powered_machine`, `storage`, `occupant_seat`,
  `powered_vehicle`, `stasis`, `hud_on_vitals`, `ui_live`.
- **Tasks:** `/datum/om/task/timed_tool` (state `tool`), `/datum/om/task/mob_work/*`, `/datum/om/task/hold`.

## 4. Scheduling (section A)

### 4.1 Behaviours

A behaviour is a DEF singleton. Its vars are declarations, compiled at boot
and never changed afterwards. Per-entity state lives on the entity.

| Var | Meaning |
|---|---|
| `every` | target interval, deciseconds; 0 = no cadence |
| `max_interval` | hard staleness bound (default 4 × every); rings near it borrow budget; breaches are counted |
| `max_dt` | seconds; a larger dt is split into equal substeps (at most 10) |
| `step_interval`, `max_catchup` | fixed-step work: `on_step(E)` once per step elapsed, at most `max_catchup` per tick |
| `clock` | clock domain; dt is scaled by the entity's rate; rate 0 takes it off the ring |
| `lane` | `LANE_URGENT`, `LANE_SIMULATION`, `LANE_DERIVED`, `LANE_PRESENTATION`, `LANE_BACKGROUND` |
| `order_after` | behaviour types this one runs after; one topological order at boot; cycles are boot errors |
| `relevance` | `list(NONE, NEAR, VISIBLE, WATCHED)`: interval per level, `OM_SLEEP`, or null for `every` |
| `wake_on` | channel mask on the entity |
| `wake_on_related` | `relation = mask`, or `list(rel, rel, ..., mask)` for a multi-hop path; `CHANGE_RELATION_ADDED/REMOVED` mean edges of that relation on this entity |
| `wake_on_native` | Rust-owned watch bits (§4.8) |
| `wake_if` | check spec; `on_wake` runs only when it passes |
| `requires` | check specs gating roster membership, re-checked only when their `depends_on` channels change |
| `handles` | event types (subtypes included) |
| `produces` | output channel; behaviours waking on it are ordered after this one |
| `holds` | hooks call `om_hold()`; holds not repeated on the next call are released |
| `min_interval` | deciseconds: `on_wake` at most this often per entity; wakes in between coalesce (their bits union) and arrive by one deadline when the interval ends |
| `runlevels` | `RUNLEVEL_*` mask: outside it the behaviour's rings are dormant (one test per ring per pass, none per entity) and resume without catch-up |

Hooks: `tick(E, dt)`, `on_wake(E, changes)`, `on_deadline(E)`,
`on_keyed_deadline(E, sub)`, `on_step(E)`, `on_start(E)`, `on_stop(E)`,
`on_native(E, bits)`, `on_event(E, event)`, and typed event handlers. All are `SHOULD_NOT_SLEEP`. A hook may omit parameters
it doesn't use. Return values are ignored: there is no scheduling by return
value.

### 4.2 Rings

Each behaviour owns one ring (cadence wheel) per interval in use. A ring has
`interval / OM_SLOT_DS` slots. An entity's slot is `phase % size`, and the
phase is per entity, so all of an entity's cadence behaviours run in the same
tick, in behaviour order.

- **Membership is eligibility.** Parking, suspension, a failing `requires`,
  a zero clock rate, an `OM_PARK` relevance level or a dormant runlevel all mean
  "not running". Nothing iterates idle entities.
- **The hot loop** per entity is a list read, one proc call and a tick-usage
  check. dt is computed once per slot. Timing is two `TICK_USAGE` reads per
  slot, so per-type cost is exact without per-call overhead. Per-call timing
  exists only under `-DOM_PROFILE_CALLS`.
- **No slot is ever skipped.** The ring processes every slot up to now. More
  than a full ring behind, each slot runs once with its real elapsed dt.
- **Elastic.** Out of budget, the ring stops mid-slot and resumes there next
  run; dt still carries the real elapsed time. A ring whose oldest due slot
  is 75% of `max_interval` late runs in a borrow pass before the lanes.

### 4.3 Lanes and budget

Each run: deadlines (a guaranteed 20% of the budget), then the borrow pass,
then each lane with its guaranteed share (30/30/15/15/10%), then any leftover
budget to lanes with work left. Every call site checks the budget after each
entity, so every phase makes progress every run and no lane can starve
another or the deadlines. The derived lane runs eager derived values and
services before its wakes.

### 4.4 Wakes and watches

`om_changed(E, bits)` (§5) queues `on_wake` for each started behaviour whose
`wake_on` matches, and ORs the bits into its pending mask. One `on_wake` per
behaviour per entity per run, with the union of bits. A behaviour later in
the entity's run order sees changes raised earlier in the same run.

- `om_wake(E, B)`: explicit wake (`CHANGE_EXPLICIT`).
- `om_watch(owner, target, mask, B)`: `owner`'s `B` wakes with
  `CHANGE_RELATED` when `target` changes `mask`. Dies with either end.
- Services: `/datum/om/service/x` with `wake_on_any = list(type = mask)` get
  `on_changes(E, bits)` once per run per entity of those types.

### 4.5 Deadlines

A bucketed wheel of `(rec, behaviour id, generation, due)` entries, one
decisecond per bucket, 1024 buckets. No datum per timer, no signal, no FFI.

- `om_deadline(E, delay, B, sub = 0)` calls `B.on_deadline(E)` after `delay`
  deciseconds. One deadline per (entity, behaviour, sub-key); calling again
  replaces it. `om_cancel_after(E, B, sub)`, `om_cancel_all_after(E, B)`,
  `om_deadline_pending(E, B, sub)`. The key is `bid + sub * OM_DL_SUB`, so firing
  one decodes it with no search: sub 0 is `on_deadline`, `OM_DL_THROTTLE` a
  `min_interval` wake, `OM_DL_STAGE + n` a pipeline stage's rewake
  (`on_keyed_deadline`).
- `om_after(E, delay, proc, args...)` is the one-shot call of §4.11, built on
  `om_deadline` (`timer.dm`).
- A stale generation or a torn-down entity is skipped when its bucket comes
  round. An entry further out than one wheel turn stays in its bucket until due.
- Clocked behaviours store the target in local time and re-check at fire. A
  rate change re-inserts every clocked deadline of that domain.
- `om_tick_now(E, B, dt)` runs a tick outside the ring.

### 4.6 Clocks

A clock domain (`CLOCK_BIO`, ...) gives each entity a rate: the product of
its `EFFECT_CLOCK_<X>_MULT` contributions times one minus the largest
`EFFECT_CLOCK_<X>_INHIBIT`, clamped to the domain's range. Local time is
settled before every rate change. The rate scales cadence dt and clocked
deadlines; a zero rate takes cadence work off the ring.
`om_clock_rate_of(E, CLOCK_X)` reads it. `om_clock_now(E, CLOCK_X)` reads the entity's local time in that domain
(deciseconds); biological code measures elapsed body time with it instead of `world.time`.
There is one clock system: holders that slow what they hold (freezers, stasis beds) hold
`EFFECT_CLOCK_<X>_INHIBIT`/`_MULT` on it through relation contributions, not a clock of their own.

### 4.7 Relevance

`RELEVANCE_NONE`, `NEAR`, `VISIBLE`, `WATCHED`. An entity's level is the
largest `EFFECT_RELEVANCE` contribution: `om_observe(E, observer, level)`,
released when the observer goes. `OM_PARK` in a behaviour's `relevance` list parks
it at that level (Life: `list(OM_PARK, null, null, null)`, so a low-priority mob on a
z-level without players costs nothing and nothing is tested per frame). `om_ui_bind()` holds `WATCHED`. A level
change moves the entity between rings and calls
`om_native_bridge_relevance(E, level)`.

### 4.8 Native (Rust) watches and the world step

There is one scheduler. The Rust world (`verdigris/ffi/src/sched.rs`) holds what is cheaper
to keep in Rust: the timer wheel, DM-owned keys, rate models and the watches on Rust-owned
state (gas mixtures, heat bodies, probe cells). It has no DM subsystem of its own: the OM
scheduler steps it at the start of every pass, once per tick (`world_step()`, one bind call,
`vg_world_step(tick, world_budget)`), and queues each wake on the lane of the watch it names.
`run_lane()` delivers a lane's world wakes before its OM wakes, under the same budget.

**Watches are owned and declared.** A subscription is a `/datum/native_watch/world`: one Rust
subscription, its own SSvg handle (the subscriber Rust reports), the owner held weakly, and the
owner's proc and lane. A wake calls `call(owner, proc)(watch, reason, source, source_kind)` on
that lane; nothing compares handles or keeps owner maps. `reason` is `WORLD_REASON_*` class bits
OR-ed with channel bits (a change watch) or the key's mask (a key); Rust merges a watch's wakes
in one tick. `source` is the cell, the key id (`source_kind` its kind) or the rate model. Read the
current state; never count wakes.

| Call | Wakes `proc` on `owner` when |
|---|---|
| `om_world_at(owner, time, proc, lane)` | the first tick at or after `time` (one-shot: the watch is freed after it fires) |
| `om_world_on_key(owner, kind, id, mask, proc, lane)` | key `(kind, id)` is published (`om_world_publish(kind, id, mask)`) with a bit of `mask` |
| `om_world_on_change(owner, handle, mask, proc, lane)` | a channel in `mask` of a Rust entity moves past its hysteresis (`WORLD_HANDLE(code, cell)`, `WORLD_GAS_HANDLE(mixture)`) |
| `om_world_when(owner, COND_*(...), proc, lane)` | a threshold, band or difference condition becomes true (Rust validates it at registration) |
| `om_world_on_rate(owner, model, WORLD_CMP_*, level, proc, lane)` | a rate model (`om_rate_linear/relax/sum`, `om_rate_read/set/set_rate/set_term/remove`) reaches `level`, at the exact tick |

- **Cancel** with `qdel(watch)`. An owner keeps the watches it may cancel and deletes them in
  `Destroy()`; a watch whose owner is gone is dropped (and freed) at its next wake.
- **Lanes.** `lane` defaults to `LANE_SIMULATION`. `LANE_URGENT` watches are drained in full every
  tick; the rest share `world_budget` (2000 wakes per tick) and wait in Rust when it runs out.
- **Keys are numbers.** A key is a kind (`WORLD_KEY_*`) and an id from `om_world_key_id()`, never
  a string (`tools/ci/check_grep.sh`). Game facts are not keys: they are OM change channels (§4.10,
  "Timers and published facts"); keys remain for rule bindings' DM-owned properties.
- **Heat watches** (`/datum/native_watch/heat`) follow an atom's heat body and are delivered by
  the heat drain through `om_native_dispatch()`; the rules adapter
  (`code/datums/rules/world_adapter.dm`) is the one place rules touch either kind.
- **Continuous work is not a watch.** What really changes every tick is a declared continuous
  periodic lane (`PERIODIC_START`, §4.10, each with a `continuous_why`), or a clock (§4.6).
- `wake_on_native` bits are unioned per entity and passed to `om_native_bridge_watch(E, bits)` on
  attach and detach; `om_native_deliver(E, bits)` runs `on_native(E, bits)` on each started
  behaviour declaring those bits.

**Signals or the scheduler?** A DCS signal when the listener must run now, in the same call
stack (cancel an attack, modify a value in flight, react to an equip), the relationship is
behavioural, and there are few listeners per sender. A channel, watch or timer when the work
can wait for the next dispatch and many changes should merge into one wake, the dependency is on
simulation state (gas, heat, power, networks) or on time, or thousands of objects depend on
shared state.

**Tests and metrics.** `om_world_wake_test(owner, change)` is the wake test for any owner: held
steady it must not wake, after `change` it must (`dq_om_world_watch_tests.dm`, with the probe
domain's `WORLD_HANDLE(VG_KIND_PROBE, cell)`). `om_world_diagnostics()` gives wakes delivered and
dropped, wakes by owner type (bounded at `OM_MAX_STAT_TYPES`, the rest under `other`), queued
wakes per lane, step time and the Rust counters; the profiler records it as
`subsystems.world_step` and each benchmark window as `<window>_world_step` plus the metric
`<window>_world_wakes`. The Rust counters are also in `verdigris_metrics()` as `world_sched.*`.

### 4.9 Diagnostics and tests

- Per behaviour type (bounded at 512 types): runs, batch ms, worst lateness
  per slot, deferrals, breaches, wakes, deadlines, errors, and (under
  `OM_PROFILE_CALLS`) worst single call. `om_diagnostics()` returns an
  admin-readable snapshot. Runtimes in hooks are caught and recorded.
- `om_test_begin()` makes a scheduler with injected time and fixed phases;
  entities that join while it is current belong to it. `scheduler_advance(seconds)`
  runs it slot by slot; `sched.jump(seconds)` moves time without running
  (skipped ticks); `harness_caps` limits calls per lane per run.
  `om_test_end()` restores the live scheduler.

### 4.10 Pipelines

A pipeline (`/datum/om/pipeline`, a behaviour) runs an ordered list of **stages** that share
one **frame**. The ring (or, for a pipeline with no cadence, a wake) makes one call per
entity; the runner walks the entity's plan testing one idle bit per stage. Everything a
hand-written frame loop used to carry is the runner's:

| Pipeline var | Meaning |
|---|---|
| `every`, `step_interval`, `max_catchup`, `lane`, `relevance`, `runlevels`, `requires`, `min_interval` | as for any behaviour: cadence, fixed steps and catch-up, lane, parking by relevance, dormancy outside runlevels |
| `stages` | stage types, or categories of them (a category contributes every family below it whose `pipeline` is this one) |
| `frame_type` | the frame (and so the facts) its stages share |
| `wake_all` | channels that wake every stage |
| `park_after` | frames in a row with every stage idle before the entity parks (hysteresis; 2) |
| `busy_retry` | no-cadence pipelines: rewake delay for a stage that ran and still has work |
| `profile_stride` | time every Nth frame per stage and entity type (`sched.stage_cost`) |

| Stage var or proc | Meaning |
|---|---|
| `perform(E, F)` | the work (`SHOULD_NOT_SLEEP`); return `STAGE_IDLE` to idle now |
| `idle(E)` | the idle rule: TRUE when nothing is left to do until a `wake_on` channel changes. Checked after each run and by the audit |
| `rewake_delay(E)` | an idle stage that still drifts: deciseconds until it wakes anyway (a deadline keyed by entity, pipeline and stage) |
| `wake_on` | channels that wake it once idle |
| `run_if` | check spec over frame facts: `FACT("alive")`, `NOT_OF(...)`, `ALL_OF(...)`; other checks get the frame as target |
| `after`, `before`, `order` | order: after/before between families, then `order`, then path; compiled once at boot, cycles are boot errors |
| `min_interval` | runs at most this often per entity; a throttled stage idles with a rewake at the end of the interval |
| `of`, `category`, `pipeline`, `extra`, `applies(E)` | families and variants (below) |

**Frames and facts.** A frame type declares `facts = list(name = list(compute proc,
depends_on))`. A fact is computed on first use and cached for the frame (`F.fact(name)`,
`F.forget(name)`, `F.set_fact(name, value)`); `run_if` of facts compiles to two bit masks.
`depends_on` names the channels that report the fact changing: a stage whose `run_if` fails
**idles** when every such channel is in its wake mask (a dead mob's alive-only stages wake on
`CHANGE_MOB_STAT`), otherwise it stays awake unless its `idle()` holds. `begin()` runs once at
the start of every scheduled frame (Life advances the stasis counter there) and `reset()` when
the frame returns to the pool. Each entity's frame **is** its pipeline state (plan, idle bits,
idle count, parking, extras, per-stage last run), stored in `rec.pipes[pipe_idx]`, so a frame
reads nothing through another datum. A nested run (`om_stage_run_now()` inside a stage) takes
a scratch frame from `sched.free_frames` (one kept per pipeline), so no shared scratch exists.

**Stages never wait.** `perform()` is `SHOULD_NOT_SLEEP`. Work that takes time (spinning a web,
laying eggs, building, cloaking) starts an om task (§11) with a claim and returns; the task's
checks cancel it on death, deletion or leaving the tile. Only speech, emotes, AI movement and
NIF upkeep, whose return values nobody reads, still go through `INVOKE_ASYNC`.

**Idle, park, wake.** A stage idles when it returns `STAGE_IDLE` or its `idle()` holds; its
bit is then skipped. An entity whose stages have all been idle for `park_after` frames in a
row parks (off the ring, in the scheduler's parked list). A channel in a stage's wake mask
clears its bit; on a parked entity it wakes every stage and unparks it. A stage rewake wakes
that stage only, and a parked entity comes back for it counting one idle frame already, so it
parks again as soon as the stage idles. A frame never runs from a wake or a rewake: the next
cadence frame runs the woken stages. A pipeline with no cadence (`every` 0) is reactive: a
wake runs the woken stages at once and they idle again.

**Abort.** `F.abort(OM_ABORT_FRAME)` stops the frame after the current stage and idles
nothing (the old early `return` before `..()`); `OM_ABORT_REST` keeps the idles already made.
A stage that deletes its entity or changes its plan also ends the frame.

**Families and variants.** A stage type directly under a category is a family root; its
subtypes are variants, each serving the entity type in its `of`. The plan for an entity type
takes, per family, the variant whose `of` is deepest in the type's inheritance (ties: the
least derived stage type; a path segment that only inherits `of` is not a variant). Plans
are built once per type (plus per-entity extras from `om_stage_add()`), so variant
resolution costs nothing per frame. A decl's `stages` rows add stages for its types.

**Audit.** `om_pipeline_audit()` (SSbehaviours every 30 s in test builds, or with the
`OM_PIPELINE_AUDIT` config flag or the admin verb) samples parked and awake entities of every
cadence pipeline and asks each idle stage without a pending rewake whose `run_if` passes
whether its `idle()` still holds. One that doesn't is a missed `om_changed()`: logged
(`OM_AUDIT: MISSED WAKE`), counted, a failed test in unit tests, and woken.

API: `om_pipe_state(E, P)`, `om_run_frame_now(E, P)`, `om_stage_run_now(E, stage)`,
`om_stage_for(E, stage)`, `om_stage_add/remove(E, stage)`, `om_stage_idle(E, P, stage)`,
`om_pipe_parked(E, P)`, `om_pipeline_frames(P)`, `om_pipeline_parked_count(P)`. Counters per
pipeline in `om_diagnostics()`: frames, parks, unparks, missed wakes.

Cost: one ring dispatch per entity, one bit test per stage, one proc call per awake stage
plus its `idle()` check. Parked entities cost nothing.

**Periodic lanes and machine steps** (roadmap S3-S5; no processing subsystem is left). A
datum with periodic work defines `periodic_step(delta)` and is started on a lane with
`PERIODIC_START(E, lane)` by whatever gives it work; `PROCESS_KILL` or `PERIODIC_STOP(E)` ends
it and it parks (`code/datums/om/periodic.dm`). The lanes are pipelines on the core runner:
`PERIODIC_SLOW` (2 s), `PERIODIC_SECOND`, `PERIODIC_FAST` (0.2 s), `PERIODIC_PLANTS` (7.5 s),
plus declared continuous lanes, each with a `continuous_why` (projectiles, instruments, priority
status effects, stat tab items). Work that only matters near mobs ends its step with
`return sleep_until_mob_near(radius)` and wakes on the mob chunks around it.

Machines never start by default. Joining the machine pipeline runs nothing: every stage starts
idle and the machine parks. Once the world is up, `materialize_wakes()` arms its watches
(`arm_wakes()`) and wakes it only if its declared `step_start_condition()` holds. After that a
machine runs only when a declared wake fires: `MACHINE_WAKE(M)` from its own producers, a power
or break change (`sleep_until_powered()`, `step_on_power_change`), an interaction or UI act
(`interaction_ran()`), a watch, or a timer. `PROCESS_KILL` or `MACHINE_SLEEP(M)` ends its step
work. `tools/ci/pollers_lint.py` ratchets `process()` definitions and `START_*PROCESSING` calls.

**Timers and published facts.** A sleeper's timer is `om_after(E, delay, proc)` (§4.11). A
published fact is a change channel on the entity it belongs to (`CHANGE_AREA_POWER` on an area,
`CHANGE_POWERNET_*` on a powernet, `CHANGE_MACHINE_MODE`/`SETTINGS` on a machine,
`CHANGE_METEORS` on `GLOB.meteor_watch`, `CHANGE_CHUNK_*` on a `/datum/mob_chunk`); whatever
waits on it `om_watch()`es those channels with its own behaviour, usually a
`/datum/om/behaviour/sleeper` subtype whose `on_wake()` does the work. Machines use
`sleep_until_keys(list(entity, mask, ...))`, which watches with the machine pipeline itself.
The missed-wake audit samples sleepers and asks each `om_sleep_violation()`.

### 4.11 One scheduler: time, sequences and asynchrony

All deferred and multi-step work in gameplay code runs on the OM wheel and is owned by an entity. There is no second scheduler: SStimer, `spawn()`, `do_after` and gameplay `sleep()` go away.

**Why `INVOKE_ASYNC` exists today.** A DM proc that sleeps also suspends its caller, unless the proc sets `waitfor = FALSE`. `INVOKE_ASYNC` is `world.ImmediateInvokeAsync`, a `waitfor = FALSE` wrapper that runs the target at once and hands control back to the caller at the target's first sleep. It exists only because gameplay procs sleep: signal handlers and Life must not block, so they wrap anything that might sleep, such as prompts, `do_after`, animations or a `sleep()` inside a proc they call. Nothing owns the resumed half. It runs even after its datum is deleted, so deleted-object runtimes follow.

A framework in which gameplay code never sleeps doesn't need it. The rule is **no gameplay proc sleeps**; the things that sleep today are expressed as data instead:

| Today | Becomes | Owned by |
|---|---|---|
| `addtimer(cb, d)`, `spawn(d)` | `om_after(E, d, proc, args...)`: a one-shot deadline on E's clock | E. Cancelled on delete; paused by suspension or stasis on its clock |
| repeating `addtimer`, countdown vars | `om_clock`, stage `rewake`, or a timed contribution | E |
| `do_after`, `sleep()` sequences, multi-step machines | `om_task` with declared `steps` (each a delay and a proc), claims, `requires` and `interrupted_by` | actor and target |
| `input()` / `alert()` / `tgui_input_*` | a typed prompt, `om_ask(answerer, /datum/om/prompt/<kind>/x, PROC_REF(cb))`: a callback prompt (tgui async), re-checked through its declared `ask_flags`, `requires` and `valid()` before `cb` runs (§11) | the receiver and the answerer |
| `INVOKE_ASYNC` | nothing: the callee no longer sleeps | — |
| `stoplag()` in long loops | the work runs as a lane with a budget and resumes by cursor | the lane |

A task step is a proc that returns: `STEP_NEXT`, `STEP_REPEAT(d)`, `STEP_DONE` or `STEP_FAIL(reason)`. Cancelling a task is always safe because no proc is ever suspended inside it. `om_after` and task deadlines share the wheel with stage rewakes, so they get lanes, budgets, relevance and parking for free: a timer on a parked entity is due on its clock, not on the wall clock.

**What stays.**
- `sleep` remains only in the MC (master.dm, failsafe.dm), vendored TGS and `stoplag()` itself. Map and station generation runs as lane work (`om_lane_work()`: a slice proc resumed by cursor within the scheduler's budget); world hooks, client init and admin verb delays are `om_after` timers; NTSL `delay()` is a task step. External I/O (rust-g SQL and HTTP) is an `om_io` job (§4.12): the caller gets a callback, nothing waits. There is no legacy wait: `db_query/sync()` is gone, and code that reads rows inline runs as a prompt flow (§4.12, "I/O in prompt flows"). BYOND's blocking built-ins (`winget`, `winexists`, `MeasureText`, `shell`) go through DX-exec (§4.12). Prompts are `om_prompt` (the `prompts` count is 0).
- Timers with no entity owner (round events, client real-time) use a global owner entity on the same wheel.

**Timer variants (S9: SStimer is deleted).** Every former `addtimer` flag has one replacement:
- `TIMER_UNIQUE`: `om_after_unique(E, d, proc, args...)`, a no-op while the same call (owner, proc, arguments) is pending; `TIMER_UNIQUE|TIMER_OVERRIDE`: `om_after_replace(...)`, which restarts it.
- `TIMER_STOPPABLE`: keep the id `om_after()` returns and `om_cancel_timer(E, id)`; `om_timer_left(E, id)` replaces `timeleft()`; `om_cancel_calls(E, proc)` drops every pending call of one proc.
- `TIMER_CLIENT_TIME`: `om_after_realtime(d, proc, args...)` on the global owner, due at a `REALTIMEOFDAY` and re-armed if the game-time wheel fires it early.
- `TIMER_LOOP`: a proc that does its work and calls `om_after_replace()` for the next round.
- `QDEL_IN`: `expire(d)` on an atom, `om_qdel_after(D, d)` on anything else; `QDEL_IN_STOPPABLE` is `expire()`, disarmed with `expire(null)`.
- `VARSET_IN` and `TIMER_COOLDOWN_*`: a `COOLDOWN_*` when the var is a rate limit, else `om_after()` of a named proc that sets it.

**Weak capture.** Object arguments to `om_after` and to tasks are held as OM handles, never as references. When the timer fires, or a task step runs, each handle is resolved first: if any argument has been deleted, the call is dropped (a timer) or fails with the reason `"gone"` (a task). A deferred call can't keep a deleted object alive or run against one.

**OM handles.** `om_handle(E)` returns an entity id plus a generation (`"id:gen"`); `om_resolve(h)` returns the object, or null once it has been deleted. The same model as the Rust core's handles: a slot table with a generation per slot and no per-target datum. Deleting an object frees its slot and bumps the generation, so a stale handle never resolves to whatever reuses the id.

**Weakrefs are replaced.** `/datum/weakref` (386 references) goes away. What it holds today splits two ways:
- *live links* (this object is attached to, controls or watches that one) become relations or slots (§7);
- *"remember who it was"* references (last attacker, forensics, logs, UI selections, refs held by tgui or clients, saved IDs) become OM handles, stored as the handle and resolved with `om_resolve(h)` when read.

**LC-refs: every object-typed var is declared.** Every datum-typed instance var or list is exactly one of:
1. a **relation or slot** (no view field: the relation's accessor is the reader);
2. an **owned child** (`REF_OWNED`/`REF_OWNED_LIST`), deleted with its owner;
3. an **OM handle** (a text var, not an object reference);
4. a **declared cache** with an invalidation rule (`declared_cache_vars()`, naming the channel or event that clears it).

A lint (`tools/ci/scheduler_lints.py`, LC-refs) counts the undeclared ones and is ratcheted to 0. Global lists of objects (`GLOB.*` holding instances) become OM registries, which drop deleted members themselves.

**Lints, ratcheted to zero outside the justified keeps (`// ALLOW(scheduler): <reason>`, §16):** `spawn(`, `addtimer(`, `INVOKE_ASYNC`, `do_after(`, `sleep(`, `stoplag(`, raw `input(`/`alert(`/`tgui_input_*`, `set waitfor`, `weakref`, raw `del(`, and undeclared object-typed vars (LC-refs). `tools/ci/scheduler_lints.py` checks each count against `tools/ci/scheduler_lints_baseline.txt`: today's counts are the ceiling, and a sweep lowers them.

### 4.12 I/O jobs

Gameplay never waits on I/O. A database query or an HTTP request is a job owned by an entity:

```dm
om_io(E, /datum/om/io/<kind>, request args..., on_done, context args...)
// on_done(result, error, context args...) runs later, on E
```

`om_io()` returns at once with a job id (0 if E or a datum context arg is already gone). The kind
takes exactly its `arg_count` request args; the next arg is the callback (a proc on E, or a global
`/proc/x`), and anything after it is passed to the callback after `result, error`.

| Kind | Request args | `result` | rust-g |
|---|---|---|---|
| `/datum/om/io/sql` | `sql, arguments` (`:name` placeholders, parameterized only) | `list("rows", "affected", "last_insert_id")`; rows are positional lists | `rustg_sql_query_async` / `rustg_sql_check_query` |
| `/datum/om/io/http` | `method, url, body, headers` | a `/datum/http_response` | `rustg_http_request_async` / `rustg_http_check_request` |

- **Owned and weak, like `om_after`.** E and every datum context arg are held as OM handles. The
  callback is dropped if any of them is gone when the job completes. E null means the global
  owner. `om_io_cancel(id)` discards a result, since the rust-g job still runs to completion.
- **The I/O lane.** The scheduler's global owner runs `/datum/om/behaviour/internal/io` off a
  one-decisecond deadline while jobs are pending. Each pass checks every pending job once, resuming
  by cursor, and stops when the scheduler budget runs out. With no jobs pending there is no
  deadline, so the lane is parked. A kind's `active_limit()` caps jobs in flight (SQL:
  `SSdbcore.max_concurrent_queries`) and the rest queue. A job unanswered after 5 minutes is
  abandoned with an error. A job that can't start (no DB connection) is answered with its error on
  the next pass, never inline.
- **Profiler.** `om_diagnostics()["io"]` reports, per kind: started, completed, errors, dropped,
  pending, queued, and average and max latency in ms.
- **Helpers.** `om_sql_write(sql, arguments)` is a fire-and-forget write that logs failures.
  `om_http_get(url)` is a fire-and-forget GET (webhooks). `SSdbcore.mass_insert_io(E, table,
  rows, duplicate_key, ignore_errors, special_columns, on_done, context...)` is MassInsert on the
  lane.
- **A sequence of queries** chains callbacks: the first query's callback starts the next one
  (`sql_commit_feedback`, `sync_admins_with_db`). Capture what the later step needs as text and
  numbers, or as context args, which are held weakly.
- **What stays synchronous.** Boot and MC-owned work that must finish before the world goes on:
  `SSdbcore.Initialize`/`Connect`/`InitializeRound` (the round id), the boot-time admin load
  (`load_admins(initial = TRUE)`), and `Shutdown` draining the queue. These use
  `Execute(async = FALSE)` (or `Execute()` before the MC runs, which blocks). Anywhere else
  `Execute(async = TRUE)` outside a prompt flow is an error: it logs a stack trace and returns
  FALSE. New code uses `om_io`.
- **I/O in prompt flows** (`code/datums/om/flow_io.dm`). A prompt flow (`prompt_flow()`, the
  entry re-runs on every answer) can read the database inline: inside a running flow,
  `query.Execute()` starts the query as an `om_io` job and unwinds the flow (it throws
  `OM_FLOW_PENDING`, which `prompt_flow()` catches); the answer re-runs the entry with the
  same arguments and the same `Execute()` - keyed by its order in the run - returns the stored
  rows, so `NextRow()`/`item` read as before. `flow_http_get(url)` does the same for HTTP,
  `flow_sql(sql, args)` for a write the flow must see finish, and `flow_io_answer(kind,
  request)` for any kind. The re-run is re-checked: a deleted datum asker, a client asker that
  left, a user who logged out, or (with `rights`) a user who lost them drops it. Rules: reads
  first, then act (chat and logs before a later read repeat on every re-run); writes nobody
  reads back are `om_sql_write()` (fire-and-forget; its jobs are not ordered with other jobs).
  The admin permission verbs, DB bans and job bans, polls, the TGS database commands
  (`run_as_flow()`: a command that waited replies to its channel when it finishes) and the
  login checks run this way.
- **Panels** can't query inside `tgui_data`. `om_sql_view(E, key, sql, args, on_rows)` fetches
  rows for E when the panel opens or its filters change; `on_rows(result, error, key)` on E
  (`om_sql_view_rows()` gives the rows) keeps them, re-checking the viewer's rights, and pushes
  an update. The permissions panel, ban
  panel, player log viewer and library computers work this way.
- **The login gate** (`client procs.dm`). `world/IsBanned()` must answer at once, so the
  database ban check moved into `log_client_to_db()`, a prompt flow on the client that also
  reads the player record, the BYOND join date and the IP reputation (`flow_http_get`). While
  it runs the client is held (`client.login_pending`): the lobby refuses ready, late join,
  observe and spawning (`login_hold_refuses()`). It then admits the client (`login_admit()`,
  which also does the paranoia logging) or disconnects it (a ban, the panic bunker, bad IP
  reputation). A gate that hasn't answered after 90 seconds fails open, as a failed check always
  has. A client reconnecting into a body it has keeps it meanwhile, and is disconnected all the
  same if the ban check says so.
- **DX-exec** (`code/datums/om/dx_exec.dm`). `winget`, `winexists` and `client.MeasureText`
  are round trips to a client, and `shell` waits on an OS process. Callers ask
  `dx_winget(E, client, id, params, on_done, context...)`, `dx_winexists()`,
  `dx_measure_text()`, `dx_shell()` or `dx_shelleo()` and get `on_done(result, context...)` on
  E later; E and datum context args are held weakly, a client by its ckey. The built-in runs in
  `dx_exec_run()`, the one `set waitfor` for them. `scheduler_lints.py` counts the built-ins
  outside it (`blocking_builtins`, 0); the allowlist keeps the executor, `world.shelleo()`
  (reached through `dx_shelleo()`, or by the MC at boot) and tgui's window setup `winexists`
  calls.

## 5. Change tracking (section B)

Channels are bits in a 24-bit mask. The low 8 are generic and mean the same
on every entity (`CHANGE_EXPLICIT`, `CHANGE_RELATION_ADDED`,
`CHANGE_RELATION_REMOVED`, `CHANGE_EFFECTS`, `CHANGE_CLOCK`,
`CHANGE_RELEVANCE`, `CHANGE_CONTENTS`, `CHANGE_RELATED`). Bits 8-23 belong
to the entity's family: `CHANGE_MOB_*`, `CHANGE_ITEM_*`, `CHANGE_MACHINE_*`,
`CHANGE_DATUM_*`. The same bit means different things in different families.

A setter writes its state, then calls `om_changed(E, bits)`:

```dm
/obj/machinery/proc/set_panel_open(value)
	panel_open = value
	om_changed(src, CHANGE_MACHINE_PANEL) // dm-health: tracked(CHANGE_MACHINE_PANEL)
```

- `om_changed` returns at once unless `E.om_listen & bits`. `om_listen` is
  the union of attached behaviours' interests, watches on E, forwarding
  entries on E, E's derived inputs, running tasks and global observers. It
  is recomputed only when those change. `OM_CHANGED(E, bits)` inlines the test.
- Changes are **level-triggered**: they say "may have changed". Observers
  re-read state and must tolerate spurious and merged wakes.
- **Relation forwarding** is compiled per behaviour from `wake_on_related`
  and per derived value from `related_inputs` and aggregates. Entries are
  installed on related entities (either direction of the edge) and rebuilt
  when an edge on the path changes, including intermediate hops. A forwarded
  change arrives as `CHANGE_RELATED`.
- **dm-health annotation.** A var whose writes must raise a channel is
  documented with `// dm-health: tracked(CHANGE_X)` on the setter. The
  analyzer that enforces "every write goes through a tracked setter" is out
  of scope here; the annotation is the contract it will check.
- `om_bulk_begin()` / `om_bulk_end()`: changes inside are coalesced per
  entity and dispatched once at the end. Events with `skip_in_bulk` are
  dropped inside a bulk.

### 5.1 Declared fields

A missed wake is a var a stage reads changing without its channel being raised. Declared fields
make that impossible by construction for the vars they cover:

- **Declared once.** `OM_FIELD(type, name, default, channel)` (`code/__defines/om.dm`) declares
  the var, generates its typed setter and registers the field, in one line:

  ```dm
  OM_FIELD(/obj/machinery/portable_atmospherics/powered/pump, on, 0, CHANGE_MACHINE_SETTINGS)
  ```

  `OM_FIELD_TYPED(type, vartype, name, default, channel)` is the same for a var with a declared
  type or modifier (`tmp`, `obj/item/cell`). The name is a bare identifier: a typo in a setter call
  or a second declaration is a compile error. The registration is a `/datum/om/field_def<type>/<name>`
  subtype that `fields_of()` reads (`code/datums/om/fields.dm`); fields merge down the type tree.
- **Written through the setter.** `E.set_on(TRUE)` writes the var and raises the declared channel,
  and does nothing (returns FALSE) when the value is unchanged. `om_set(E, "on", TRUE)` is the same
  where the name is data. A field edited in place (a list) calls `om_field_changed(E, "name")`.
- **Deterministic expansion.** The var is always named exactly `name` and its setter is always the
  proc `set_<name>` on the declaring type. Tools rely on this instead of expanding the macro: the
  external AST analyzer (`tools/dm-health`) can treat an OM_FIELD field as
  `tracked(setter=set_<name>)`, and `field_write_lint.py` does the equivalent today. Keep the naming
  if the macro changes.
- **wake_on derived from reads.** A stage names what it reads (`reads = list("on")`; behaviours add
  `reads_of`). At boot the registry ORs the channels of the read fields into its `wake_on`
  (`build_stages()`/`build_behaviours()`), so the two can't drift; `wake_on` lists only the extra
  channels that aren't field reads (a stage whose only wakes are its reads sets `wake_on = 0` to
  drop an inherited mask). `check_field_reads()` still fails boot (and
  `dq_om_declared_fields_cover_reads`) on a read of an undeclared field.
- **Linted everywhere.** `tools/ci/field_write_lint.py` (count `field_write` in `api_lints.py`,
  ceiling 0) finds every write to a declared field that isn't its generated setter or its initial
  value (the OM_FIELD default, a subtype's type-body override): `on = x`, `src.on = x`, `on |= x`,
  `on++` in a proc of a related type, and `thing.on = x` for any receiver not provably of an
  unrelated type (locals, arguments and member vars are resolved). It scans every file, unit tests
  and `Initialize()`/`New()` included: a test that writes a field directly skips the channel the
  code under test depends on and hides a missed wake. A test that needs a deliberately missed wake
  (the audit test) writes through `vars[]`.

Declared today: the machine step stage (`step_active`, `step_waiting_power`, `speed_process`),
rechargers and cell chargers (`charging`), fire alarms (`timing`), air alarms
(`regulating_temperature`), canisters (`valve_open`, `om_settled`), portable pumps and scrubbers
(`on`) in `code/game/machinery/machine_pipeline.dm`; on mobs (`living_systems.dm`) `instability`, `virtual_reality_mob`, the `glow_*` vars, `tf_mob_holder`,
`sdisabilities`, `ear_damage` and simple mobs' `purge`. Stage rules that read procs
(`step_has_work()`, `power_settled()`, `body.life_settled()`) or relations are covered by the
producers of what those read, and by the audit.

**The audit.** `om_pipeline_audit()` skips a stage whose wake is already queued (the entity's
pending bits for the pipeline cover its `wake_mask`): the wake queue drains at the start of a lane,
so a change a frame raises later in the same pass is delivered on the next one, not missed.

## 6. Derived values (section C)

A derived value has `inputs` (own channels), `derived_inputs` (other derived
names), `related_inputs` (relation = mask), a `channel` it raises, and
`max_age` for inputs the engine owns. It is stored on the entity, indexed by
the derived type's integer id.

- **Lazy by default.** A change on an input sets the dirty bit; the next
  `om_derived(E, name)` recomputes. Dirtiness cascades to derived values that
  read it.
- **Eager by itself** when something observes its channel (a behaviour's
  `wake_on`, a watch, a forward): the dirty entry is recomputed once in
  `LANE_DERIVED`, inputs first, and the channel is raised only if the value
  changed.
- **Aggregates** (`DERIVE_SUM/COUNT/ANY/ALL/MIN/MAX`, or `aggregate =
  AGG_CUSTOM` with `on_member_added/removed/changed`) run over the members of
  a relation (sources of edges whose target is the entity) or over a ledger
  slot (`OVER_SLOT(id)`, recomputed lazily on `CHANGE_CONTENTS`). Each
  member's contribution is cached on its edge, so joining, leaving and
  changing are O(1) deltas; MIN and MAX rescan only when the extreme leaves
  or gets worse. Declare `member_inputs` to track member changes.
  `-DOM_DERIVED_AUDIT` recomputes on every read and reports differences.

## 7. Relations (section D)

`om_link(source, target, /datum/om/relation/x)` returns the edge or a text
reason. `om_unlink(...)`, `om_related(E, rel)` (targets, E is source),
`om_related_to(E, rel)` (sources, E is target), `om_relation_of(E, rel)`
(single target).

- Both ends hold the edge. `source_single` / `target_single` set cardinality;
  `conflict` is `OM_REL_REPLACE` or `OM_REL_REFUSE` (with a reason).
- **No view fields.** A relation or slot IS the state; nothing mirrors it
  into a var. The generic field mechanism (`source_ref_field` and friends,
  `om_field_link()`) is deleted, and so are the vars it used to feed:
  `occupant`, `buckled`, `buckled_mobs`, `pulling`, `pulledby`, the grab's
  `affecting`/`assailant`, `following`, `following_mobs` and the borer's
  `host`, the eye's `owner`, the mob's `eyeobj` and the AI's `all_eyes`. Read through the accessor macros in `code/__defines/om.dm`:
  `OM_REL_TARGET(E, rel)` / `OM_REL_SOURCE(E, rel)` / `OM_REL_SOURCES(E, rel)`
  / `OM_REL_TARGETS(E, rel)` for a bare relation, `SLOT_ITEM(E, slot_id)` /
  `SLOT_LIST(E, slot_id)` for a slot, plus the named wrappers (`BUCKLED`,
  `BUCKLED_MOBS`, `PULLING`, `PULLED_BY`, `GRABBED_BY`, `GRAB_TARGET`,
  `GRAB_ASSAILANT`, `EYE_OWNER`, `EYES_OF`, `ACTIVE_EYE`, `ORBIT_TARGET`, `ORBITERS`, `FOLLOWING`,
  `FOLLOWERS`, `BORER_HOST`, `BORER_OF`, `LEASH_PET`, `LEASH_MASTER`,
  `LEASH_OF`, `TETHERED_HANDHELD`, `TETHER_HOST`). They expand to proc
  calls, so read into a typed local before member access. `on_link()`/
  `on_unlink()` keep only real side effects. `edge.data` carries
  relation-specific payload the linker attaches (an orbit's saved
  transform).
- **Deletion unlinks.** In the destroy transaction's phase 4 (links), before
  any `Destroy()`, every edge is unlinked. `on_source_delete` /
  `on_target_delete` (`OM_END_UNLINK` or `OM_END_DELETE_OTHER`) apply to the
  other end. `on_link` / `on_unlink(source, target, edge)` always get both
  ends non-null; the deleting end is `QDELETED`. This reuses the lifecycle
  phases and constants in `code/datums/lifecycle/`; there is no second
  ownership tree.
- **Contributions and grants** from `contributes`, `source_contributes`,
  `grants_target`, `grants_occupant` are held with the edge as source while
  `active_if` passes, re-checked when its `depends_on` channels change on
  either end, and released when the edge goes.
- **Slots are relations.** `/datum/om/relation/slot` (`code/datums/containment/slot_def.dm`,
  containment.md §3) is a relation that also owns loc: linking a thing into a
  slot (a ledger move -- enter, exit, reslot) links it to the holder by that
  same relation, so a slot gets everything above for free (`changes`
  channels, contributes/grants, and its own `on_link()`/`on_unlink()` as the
  sole writer of any legacy var occupants still expose) on top of capacity,
  exposure and propagation. A slot decl declares `holder` (a type, or list of types)
  instead of overriding a per-holder proc; the registry groups every decl by
  its declared holder and resolves a holder instance's group by its
  `slot_holder_key()` (its own type by default; a mob returns its body plan's
  type), picking the most-derived declared holder that key is a subtype of --
  the same resolution a proc-override chain would give. The ledger also
  raises `CHANGE_CONTENTS` on the holder on every insert and remove.

## 8. Contributions (section E)

| Call | Meaning |
|---|---|
| `om_apply(T, id, source, duration, value = TRUE, key)` | timed; expires through the deadline wheel |
| `om_hold(T, id, source, value = TRUE, key)` | held while `source` exists |
| `om_release(T, id, source, key)` | release one |
| `om_has(T, id)` | value differs from the default |
| `om_value_of(T, id)` | combined value |
| `om_grant(T, kind, id, source)`, `om_revoke`, `om_has_grant`, `om_grants_from(T, source)` | grants: kind = effect id, id = key, source = source |
| `om_observe`, `om_unobserve`, `om_relevance` | relevance |
| `om_suspend(E, source)`, `om_unsuspend` | suspension hold: off every ring while held |
| `implies` (row key) | effect ids the entity holds on itself while this one is in effect (`EFFECT_GODMODE` implies the incapacitation immunities) |

Effect rows declare `combine` (`COMBINE_ANY`, `SUM`, `MAX`, `MIN`,
`MULTIPLY`, `SUM_PER_KEY`), `stacking` for repeated applies from one source
(`STACKING_REPLACE`, `EXTEND`, `MAX`), `channel`, `default` and optional
`expr` or `type`.

- Deleting a source releases everything it holds, and deleting a target
  forgets everything held on it. **Overridable state has no public setter**:
  it changes only through apply/hold/release, so an override can't outlive
  whatever imposed it.
- **Holds from hooks are reconciled.** In a `holds = TRUE` behaviour, every
  hold the hook made last time but not this time is released when it
  returns. Stopping the behaviour releases all its holds. So "stunned while
  X" is `if(X) om_hold(...)` in `tick`, and nothing can get stuck.
- The grant vocabulary matches `rewrite/grants` in spirit: kinds become
  effect types, ids become keys, and the source is the edge or datum that
  granted. Ids are text or type paths.

### 8.1 Timed statuses

A row with `"kind" = OM_EFFECT_STATUS` (`code/datums/om/status.dm`) is a timed status. Its
fields are declarations, so nothing switches on which status it is:

| Field | Meaning |
|---|---|
| `unit`, `rate`, `rate_resting`, `max_units` | one unit lasts `unit` ds at rate 1; `rate` units wear off per unit of time (the entity's `status_rate()` may change it); cap |
| `immunity` | effect id that blocks increases; gaining it ends the timed contributions (`blocks` is compiled on the immunity) |
| `scaled`, `signal` | increases pass the entity's `status_scale()`; `signal` is sent before an increase and `COMPONENT_NO_STUN` vetoes it |
| `alert`, `alert_type`, `indicator` | presentation, applied by the entity's `status_shown()` |
| `on_start`, `on_end`, `on_increase` | procs called on the entity |

The API is on `/datum`: `has_status(id)`, `status_immune(id)`, `status_remaining(id)`
(deciseconds until the last timed contribution ends: 0 when none; a hold has no duration),
`status_units(id)` (`status_remaining()` in units, rounded up, no floor), `status_seconds(id)`,
`status_at_least(id, n)`, `status_set(id, n)`, `status_adjust(id, n)`, `status_end(id)`,
`status_rate_check(id)`. Each call looks the def up once and then works on its integer index.
The entity's own dose is its keyless timed contribution; its value is the rate its expiry was
computed with, so a rate change rescales what is left. Mob statuses: [life_on_om.md](life_on_om.md) §7.

## 9. Rates (section F)

`om_rate_new(owner, name, value, per_second, channel, thresholds, min, max)`
returns a `/datum/om/rate`: `R.now()`, `R.set_rate(r)` (settles first),
`R.set_value(v)`, `R.time_until(level)` (deciseconds, or null). Crossing a
threshold raises `channel` on the owner. The crossing is found by the
deadline wheel; nothing polls. `om_ui_rate(R)` returns
`list(value, rate, at)` for client-side interpolation.

## 10. Events and checks (sections G, H)

- `om_emit(E, new /datum/om/event/x)` delivers to started behaviours on E
  handling x or any ancestor (inheritance is flattened at boot), in run
  order, by double dispatch: the event type overrides `dispatch(B, E)` to
  call `B.on_x(E, event)`, declared next to the event.
- **Re-entrancy.** An event emitted during delivery is queued (coalesced per
  entity and type unless `coalesce = FALSE`) and delivered right after, in
  the same call. `/datum/om/event/before/x` is synchronous and may return
  `EVENT_VETO`; emitting one on an entity already delivering one is an
  error, reported and answered with a veto, never dropped silently.
- **Senders.** `om_wants(E, /datum/om/event/x)` is TRUE when a started behaviour on E
  handles x (or a task could be interrupted by it); hot senders (movement, examine,
  crossing, attacks) test it before allocating the event. Shared atom events (examine,
  moved, hitby, before/cross, before/attack_self, before/attackby, before/attack_hand)
  live in `code/datums/om_events/atom_events.dm`; a behaviour's own events sit next to it
  (`code/datums/behaviours/`). A before/ event can also carry a result field the sender
  reads back (`before/dice_roll.result_override`).
- **Checks:** `/datum/om/check/x/why_not(actor, target)` returns null or a
  reason; `depends_on` lists the channels that can flip it; `arg` is the
  parameter. `om_why_not(spec, actor, target)`, `om_can(...)`,
  `om_check_get(spec)`.

## 11. Tasks and UI (sections I, J)

- **A task is its type.** `/datum/om/task/<x>` declares `duration`, `claims`, `requires`,
  `interrupted_by`, `steps` and `complete_proc`/`cancel_proc` (procs on the receiver, called
  with the task; or override `on_complete()`/`on_cancel()`), and its vars are the run's state:

  ```dm
  /datum/om/task/timed/lockpick
  	duration = 5 SECONDS
  	complete_proc = /obj/item/lockpick/proc/pick_done
  	var/obj/structure/simple_door/door

  om_task_start(/datum/om/task/timed/lockpick, user, src, door = D)
  ```

  `om_task_start(type, actor, target, var = value...)` returns the task or a reason. The named
  arguments set vars (state, or any declaration to override per run: `duration`, `receiver`,
  `flags`).
  It checks `requires`, claims the target (a `target_single`, refusing claim relation: the
  loser gets "is in use"), and sets one deadline. It completes by that deadline or its last
  step, and is cancelled when its requires fail (re-checked on their channels on actor or
  target), when an `interrupted_by` event reaches the actor, or when the actor, the target or
  **any datum in its state** is deleted: every datum var is held by the `task_holds`
  relation, which clears the var and cancels the task (`unheld = list("beam")` opts out a
  var whose datum ends itself). `on_complete` / `on_cancel` run once. Nothing polls.
- **Timed actions** (what `do_after` was) are `/datum/om/task/timed/<x>`: a progress bar and a
  cog, cancelled when the user moves, changes hands or is incapacitated, or the target moves
  (`flags`: `IGNORE_*`), leaves `max_distance` or the aim leaves `target_zone`; `check_proc` on
  the receiver re-checks; `fail_message` is told to the user on cancel. A zero duration
  completes inside `om_task_start()`, so "instant or timed" is one call with
  `"duration" = instant ? 0 : d`. Repeating work (one sheet, round or pulse at a time) is a
  steps task returning `STEP_REPEAT(d)`, with a fresh bar per step.
  `om_do_after(user, delay, target, receiver, on_done, done_args, ...)` remains only for the
  zero-state case: at most two arguments across `done_args`, `fail_args` and `check_args`
  (`tools/ci/api_lints.py`, `do_after_state`, is 0). A done proc taking a third argument, or a
  `*_timed_done2` proc threading the same arguments through, is a task type instead.
- **Named task arguments.** `om_task_start()` is a macro: its named arguments set the task's
  typed vars, and the caller's `src` rides along as the receiver default (the first of src,
  target and actor that has the `complete_proc`/`cancel_proc`/`check_proc`/a step proc, else
  src). A `complete_proc` of the task's own type runs on the task with no arguments, so it reads
  the state as its own vars. A var the type doesn't declare is a CRASH on first run. The old
  `list("key" = value)` form still works (receiver defaults to the actor) and is ratcheted by
  `api_lints.py` (`task_params_list`).

  Before (`code/game/objects/items/stacks/medical.dm`, `code/modules/clothing/glasses/glasses.dm`):

  ```dm
  om_task_start(/datum/om/task/timed/splint_attack, user, affecting, list("receiver" = src, "M" = M, "limb" = limb))

  om_do_after(user, 5 SECONDS, target, src, PROC_REF(prescribe_done), list(user, G))

  /obj/item/glasses_kit/proc/prescribe_done(mob/living/carbon/human/user, obj/item/clothing/glasses/G)
  ```

  After:

  ```dm
  om_task_start(/datum/om/task/timed/splint_attack, user, affecting, M = M, limb = limb)

  om_task_start(/datum/om/task/timed/glasses_kit/prescribe, user, G, kit = src)

  /datum/om/task/timed/glasses_kit/prescribe
  	complete_proc = /datum/om/task/timed/glasses_kit/prescribe/proc/done

  /datum/om/task/timed/glasses_kit/prescribe/proc/done()   // runs on the task: kit, actor, target are its vars
  	var/obj/item/clothing/glasses/G = target
  	if(!kit.scrip_loaded)
  		return
  	G.prescribe(actor)
  	kit.scrip_loaded = 0
  ```
- **Typed prompts** (`code/datums/om/ask.dm`). A question is a `/datum/om/prompt/<kind>` type:
  `confirm` (answer `yes`; the answer proc runs on yes unless `answer_on_no`, `declined()` on
  no), `choice` (`choice`; `buttons = TRUE` for alert buttons), `text` (`text`), `number`
  (`number`), `color` (`picked_color`) and `checklist` (`picked`). `title`, `message`,
  `ask_flags`, `requires`, `timeout` and `cancel_answer` are declared on the type (or passed by
  name); `prepare()` builds the message from the state; `valid()` is the type's own re-check,
  run with the answer already stored. Roles: `answerer` (sees the window), `asker` (started it;
  default the answerer, or the flow's actor) and `subject` (what it's about; default the
  receiver when it's an atom). `ask_flags` cover the common re-checks: `ASK_ALIVE`,
  `ASK_CONSCIOUS`, `ASK_CAPABLE` (answerer and asker), `ASK_ADJACENT` (answerer next to the
  asker, or to the subject when they're the same mob), `ASK_NEAR_SUBJECT`, `ASK_HELD` /
  `ASK_CARRIED` (the subject is still in the asker's hands / on them), `ASK_FACE_TO_FACE`. Any
  failure drops the answer and calls `refused(reason)`. Datums in the type's scalar vars (and
  the three roles) are held as handles while the window is open, so a deleted one drops the
  answer. `om_ask(answerer, type, PROC_REF(cb), var = value...)` is a macro: `cb` runs on the
  caller's `src` with the prompt as its one argument. The string-keyed
  `om_prompt(E, user, list(...), cb)` form still works and is ratcheted (`api_lints.py`,
  `prompt_spec`).

  Before (`code/modules/mob/living/carbon/human/species/species_shapeshift.dm`):

  ```dm
  om_prompt(src, src, list("kind" = "list", "message" = "Please select a species to emulate.", "title" = "Shapeshifter Body", "choices" = species.get_valid_shapeshifter_forms(src), "requires" = PROMPT_CONSCIOUS), PROC_REF(shapeshifter_shape_chosen))

  /mob/living/carbon/human/proc/shapeshifter_shape_chosen(mob/user, new_species, datum/om/prompt/ask)
  	if(!GLOB.all_species[new_species] || GLOB.wrapped_species_by_ref["\ref[src]"] == new_species || !(new_species in species.get_valid_shapeshifter_forms(src)))
  		return
  	shapeshifter_change_shape(new_species)
  ```

  After:

  ```dm
  om_ask(src, /datum/om/prompt/choice/shapeshifter_form, PROC_REF(shapeshifter_shape_chosen), choices = species.get_valid_shapeshifter_forms(src))

  /datum/om/prompt/choice/shapeshifter_form
  	title = "Shapeshifter Body"
  	message = "Please select a species to emulate."
  	ask_flags = ASK_CONSCIOUS

  /datum/om/prompt/choice/shapeshifter_form/valid()
  	var/mob/living/carbon/human/shifter = asker
  	if(!GLOB.all_species[choice] || GLOB.wrapped_species_by_ref["\ref[shifter]"] == choice || !(choice in shifter.species.get_valid_shapeshifter_forms(shifter)))
  		return "not a form to take"
  	return null

  /mob/living/carbon/human/proc/shapeshifter_shape_chosen(datum/om/prompt/choice/shapeshifter_form/ask)
  	shapeshifter_change_shape(ask.choice)
  ```
- **Flows** (`code/datums/om/flow.dm`): a multi-step action (take time, ask someone, act) is one
  `/datum/om/flow/<x>` type. Its typed vars are the state every step shares (held as handles
  between steps); each step is a proc on the flow; `requires` (actor, target) and `valid()` are
  re-checked before every step after the first. A step goes on with `wait(duration, next, ...)`
  (a timed action by the actor on the target, then `next(task)`) or `om_ask(answerer, prompt,
  next, ...)` (then `next(prompt)`; the asker defaults to the actor and the subject to the
  target); a step that does neither finishes the flow. A cancelled wait, a declined, cancelled
  or refused prompt, a failed re-check or a deleted datum calls `ended(reason)` once.
  `om_flow_start(type, actor, target, var = value...)` starts one and returns it or a reason.

  Before (`code/game/objects/items/leash.dm`): three procs, state through positional args and a
  data list, re-checks by hand:

  ```dm
  	om_do_after(user, leashtime, target = C, receiver = src, on_done = PROC_REF(attack_timed_done), done_args = list(C, user))

  /obj/item/leash/proc/attack_timed_done(mob/living/C, mob/living/user)
  	om_prompt(src, C, list("message" = "Would you like to be leased by [user]? ...", "title" = "Become Leashed", "choices" = list("No","Yes"), "target" = user, "requires" = PROMPT_ADJACENT, "data" = list("holder" = user)), PROC_REF(leash_accepted))

  /obj/item/leash/proc/leash_accepted(mob/living/C, answer, datum/om/prompt/ask)
  	var/mob/living/user = ask.get("holder")
  	if(answer != "Yes")
  		return ITEM_INTERACT_FAILURE
  	if(QDELETED(C) || QDELETED(user) || loc != user || C?.leash_item())
  		return ITEM_INTERACT_FAILURE
  	...
  ```

  After:

  ```dm
  	om_flow_start(/datum/om/flow/leash, user, C, leash = src)

  /datum/om/flow/leash
  	var/obj/item/leash/leash

  /datum/om/flow/leash/valid()            // before every step: still holding it, pet still free
  	var/mob/living/pet = target
  	if(leash.loc != actor)
  		return "not holding the leash"
  	if(pet.leash_item())
  		return "already leashed"
  	return null

  /datum/om/flow/leash/start()
  	...
  	wait(leashtime, PROC_REF(offer))

  /datum/om/flow/leash/proc/offer()
  	om_ask(target, /datum/om/prompt/confirm/leash_offer, PROC_REF(accepted))

  /datum/om/flow/leash/proc/accepted(datum/om/prompt/confirm/leash_offer/ask)
  	leash.attach(target, actor)

  /datum/om/prompt/confirm/leash_offer
  	title = "Become Leashed"
  	no_first = TRUE
  	ask_flags = ASK_FACE_TO_FACE

  /datum/om/prompt/confirm/leash_offer/prepare()
  	message = "Would you like to be leashed by [asker]? You can OOC escape to escape"
  	return TRUE
  ```

  Other flows: tome scribing (`gamemodes/cult/ritual.dm`: rune pick, destination pick, cut,
  timed drawing; `requires` keeps the tome in hand at every step), pickpocketing
  (`clothing/gloves/antagonist.dm`: five chained tasks) and inbelly spawning
  (`vore/eating/inbelly_spawn.dm`: six consent prompts across two players, with `ended()`
  telling both sides by the step it stopped at).
- **Busy is a claim, not a flag.** A task can also claim what does the work: its actor
  (`claims_actor`), or a tool, bot or machine (`om_task_claim()`, `om_do_after(..., busy = X)`,
  `use_tool(..., busy = X)`), on the `busy` relation so a busy worker can still be someone's
  target. `om_busy(X)` is the query (a running task claims X, as worker or exclusive target);
  `om_in_use(X)` asks only about target claims. The claim is released on complete, cancel or
  delete. An ability whose continuation is a timer holds its worker with `om_hold_busy(X, d,
  on_end)` (a claiming task done at its deadline; `om_release_busy()` ends it early). There
  are no `busy`/`in_use` vars guarding timed actions.
- `om_ui_bind(session, target, mask)` is a watch that holds the target at
  `WATCHED`. Changes coalesce into one `session.om_ui_push()` per run, and at
  most one per 0.2 s per session (the rest arrive by deadline). `/datum/tgui`
  pushes `send_update()`. `om_ui_bind_table(session, E)` binds the rows of
  E's `ui` table; `om_ui_stream(E)` returns its streamed rates.

## 12. Bug classes removed

Each has a regression test in `dq_om_core_tests.dm`.

| Bug class | Why it can't happen |
|---|---|
| Cadence slots skipped when ticks are skipped | rings process every slot up to now; dt is real elapsed time |
| One lane starving the others or the timers | guaranteed shares, deadlines first, a budget check per entity |
| A wake running the whole cadence work | `on_wake` and `tick` are separate hooks |
| An odd return value killing a behaviour | return values are ignored |
| A runtime killing a behaviour or its ring | hooks are caught per slot; the loop resumes at the next entity |
| Null holder in relation hooks | hooks get both ends as arguments, before `Destroy()` |
| Waits without timeouts | nothing sleeps on a task; tasks end by deadline |
| Shared mutable per-type config | DEFs are compiled once; per-entity state is on the entity |
| Subtype events missing handlers | handler tables flatten inheritance |
| Re-entrant events silently dropped | queued and delivered; veto re-entry is an error |
| Inverted duplicate constants | the lifecycle's own phases and constants are reused |
| An FFI call per DM timer | the deadline wheel is pure DM |
| Draining or transaction flags stuck after a runtime | every drain resets its depth outside the try, hook context is restored after catch |
| Overrides stuck after their source goes | holds die with their source; hook holds are reconciled |
| A second scheduler inside content (per-stage sleep bits, wake timers, parking, audits hand-rolled per system) | pipelines own them once (§4.10); content declares stages |
| A wake coalescer written by hand per behaviour | `min_interval` |
| Variant choice by string length of a type path | inheritance depth, once per plan |

## 13. Cost

- An idle entity costs nothing per tick. Joining costs two vars on `/datum`
  (`om_rec`, `om_listen`), free until used, and one record.
- A setter nobody listens to costs one bitwise test.
- Cadence dispatch is the `process()` shape: a list read, a proc call and a
  tick check per entity, with timing per slot. Run
  `tools/build/build.sh bench --scenario=om_dispatch` to compare with an
  SSprocessing-style loop. On 2026-09-25 (20000 entities, 5 boots) the loop
  cost 847 ns per call (±39) and the ring 1036 ns (±80): **1.12x**. It was
  1.48x while the loop re-read the ring's position var and the slot list twice
  per entity to survive removals; removals from the slot in progress now leave
  a null tombstone and joins wait for the slot to finish, so the loop keeps its
  index in a local.
- Deadlines are four list entries in a bucket and three on the entity.

## 14. What Life uses

| Life needs | API |
|---|---|
| Ordered systems per mob, one call per mob | the `life` pipeline (§4.10): stages, `order`, one dispatch per mob |
| Early returns and `if` blocks of the old Life() | frame facts and `run_if` (`placed`, `alive`, `status_ok`, `in_stasis`, `environment`) |
| Systems idling and waking | stage `idle()`, `wake_on`, `rewake_delay()` |
| Hibernation | parking (`park_after` 2) |
| Lobby and player-free z-levels | `runlevels`, relevance `OM_PARK` with z-level presence holds |
| canmove and HUD | reactive `life_derive` and `life_present` pipelines (the latter `min_interval` 0.5 s) |
| Statuses | timed statuses (§8.1) |
| Biology running faster or slower | `CLOCK_BIO`; stasis holds `EFFECT_CLOCK_BIO_INHIBIT` |
| Stasis and cryo, absorbed prey | the biology clock, `om_suspend()` |

## 15. Limits

- One deadline per (entity, behaviour, sub-key). The internal expiry, rate and
  task behaviours keep their own list and set the soonest.
- A pipeline frame's facts are at most 24 per frame type; stage idle bits are
  16 per list entry.
- Timed contributions are read as present until their expiry deadline runs,
  at most one scheduler run late.
- A slot deferred mid-way gives the rest of the slot the dt computed when
  the slot began.
- A newly joined entity's first dt covers the time since its slot last ran,
  at most one interval.
- `max_dt` substeps cap at 10 per tick; beyond that each substep is larger.
- Forwarding follows edges in both directions. Paths are rebuilt on every
  edge change along them, which is linear in the path's fan-out.
- `OVER_SLOT` aggregates are lazy and don't track member changes.
- Family channels share bit positions, so a behaviour's `wake_on` assumes the
  family of the entities it attaches to.
- The dm-health analyzer for `tracked()` annotations is not built.
- Slot defs link through a relation (`om_relation`); they don't carry
  contribution rows themselves.
- Declared fields (§5.1) cover the vars listed there. Stage rules that read procs
  (`step_has_work()`, `power_settled()`, `body.life_settled()`) and the sleepers'
  `om_sleep_violation()` rules (door, camera, light timers; turret and point-defence targets)
  rely on their producers and the audit, not on declarations.

## 16. One way to do X

Each job has one mechanism. Every alternative in the third column is counted by the lint in the
fourth, and `tools/ci/check_ratchets.sh` runs them all: a count may fall, never rise. The
ceilings are the `tools/ci/*_baseline.txt` files next to each lint (`api_lints_baseline.txt`,
`scheduler_lints_baseline.txt`, `dcs_lints_baseline.txt`, `cooldown_baseline.txt`,
`containment_baseline.txt`, `spatial_baseline.txt`, `latent_baseline.txt`,
`declared_refs_baseline.txt`, `lifecycle_counts_baseline.txt`); lower
one with the lint's `--update` after a sweep, never raise it.

**Justified keeps.** There are no allowlist files. A site that is right as it is says so where
it stands, with one annotation every lint reads (`tools/ci/allow_annotations.py`):

```dm
spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call

// ALLOW(lifecycle): the ledger is the containment engine itself; it lets go of its holder.
/datum/ledger/Destroy()
```

- It goes on the site's own line or on a comment-only line directly above it. Inside a
  multi-line macro, where `//` would swallow the `\` continuation, write
  `/* ALLOW(scheduler): reason */`.
- One annotation can name several lints: `// ALLOW(declared_refs, state_ref): reason`.
- The reason after the colon is required. `allow_annotations.py` (run by `check_ratchets.sh`)
  fails on a missing reason, an unknown lint name or a malformed annotation.
- Lint names: `api`, `check_grep` (same line only), `containment`, `cooldown`,
  `dcs`, `declared_refs`, `instance_list`, `latent`, `lifecycle`, `object_keyed_lists`,
  `pollers`, `registry`, `scheduler`, `spatial`, `state_ref`.
- An annotated site doesn't count toward its ceiling, so each counted total ratchets to 0.
  The scheduler's keeps are §4.11's "What stays": the MC, GC and failsafe, world and client
  procs, savefiles, vendored TGS, and leaves that block on external I/O.
- A declaration-level keep (a per-instance list, a saved reference var, an undeclared
  reference var) goes on the `var/` line itself.
- Legacy debt with no reason yet is not annotated; it stays in the ceiling until a sweep
  converts it.

| To... | The one way | Not | Lint (count) |
|---|---|---|---|
| Do something after a delay | `om_after(E, delay, proc, args...)` (§4.11) | `addtimer()`, `spawn()`, `sleep()` | `scheduler_lints.py` (`addtimer`, `spawn`, `sleep`) |
| Take time over an action with state | a named task type, `om_task_start(/datum/om/task/timed/x, actor, target, var = value...)` (§11) | `om_do_after()`/`use_tool()` carrying more than two args, `do_after()`; a `list("key" = value)` params list | `api_lints.py` (`do_after_state`, `use_tool_state`, `task_params_list`), `scheduler_lints.py` (`do_after`) |
| Ask a player | a typed prompt, `om_ask(answerer, /datum/om/prompt/<kind>/x, PROC_REF(cb), var = value...)` (§11) | `input()`, `alert()`, `tgui_input_*()`, `tgui_alert()`; the string-keyed spec of `om_prompt()`/`om_prompt_sequence()`/`om_prompt_chain()` | `scheduler_lints.py` (`prompts`), `api_lints.py` (`prompt_spec`) |
| Do an action in steps (take time, ask, act) | one flow type, `om_flow_start(/datum/om/flow/x, actor, target, var = value...)`, its steps chained with `wait()` / `om_ask()` (§11) | several procs passing state through `done_args`, prompt `data` or chained task params, each re-checking by hand | `api_lints.py` (`prompt_spec`, `task_params_list`) |
| Do I/O (SQL, HTTP) | `om_io(E, /datum/om/io/<kind>, args..., on_done)` with kind `sql` or `http` (§4.12); `om_sql_write()`, `om_http_get()`; inline reads inside a prompt flow; `om_sql_view()` for panels | `Execute()` outside a flow, `world.Export()`, `set waitfor` / `INVOKE_ASYNC` around a query | `scheduler_lints.py` (`set_waitfor`, `invoke_async`, `stoplag`) |
| Read a client's window or text size, or run a process | DX-exec: `dx_winget()`, `dx_winexists()`, `dx_measure_text()`, `dx_shell()`, `dx_shelleo()` (§4.12) | `winget()`, `winexists()`, `MeasureText()`, `shell()` | `scheduler_lints.py` (`blocking_builtins`) |
| Run slow work without blocking | nothing: gameplay procs don't sleep | `INVOKE_ASYNC`, `set waitfor`, `stoplag()` | `scheduler_lints.py` (`invoke_async`, `set_waitfor`, `stoplag`) |
| Rate-limit something | `COOLDOWN_START()` / `COOLDOWN_FINISHED()` (a time compared) | `TIMER_COOLDOWN_START()`; a raw `world.time` compare against a hand-kept timestamp or deadline | `api_lints.py` (`timer_cooldown`), `cooldown_lint.py` |
| Declare a var that a stage, behaviour or watch reads | `OM_FIELD(type, name, default, channel)`, and name it in the stage's `reads` (wake_on is derived) (§5.1) | a plain `var/x` plus a hand-written setter; listing the field's channel in `wake_on` by hand | `api_lints.py` (`field_write`), boot `check_field_reads()` |
| Change a var that a stage, behaviour or watch reads | its generated setter, `E.set_x(v)`, or `om_set(E, "x", v)` (§5.1), in game code and tests alike | `x = v`, `E.x = v`, `x |= v` on a declared field anywhere (unit tests, `Initialize()` included); `vars[name] = v` outside the reflection sites marked `ALLOW(api)`; `om_set_var()` and friends | `api_lints.py` (`field_write`, `vars_write`, `vars_helpers`) |
| Read a relation or a slot | the typed accessor proc, `M.buckled_to()`, `I.slot_item(slot)` (§7) | `BUCKLED()`, `PULLING()`, `SLOT_ITEM()`... macros; `om_relation_of()` outside `code/datums/om` | `api_lints.py` (`accessor_macros`, `raw_relation`) |
| Wake on Rust-owned state, a DM key, a rate crossing or a tick-precise time | a world watch, `om_world_at/on_key/on_change/when/on_rate()`, delivered on the watch's lane (§4.8) | `SSreactor`, `REACT_*`, `on_react()`; a raw `vg_world_*` subscription bind | `api_lints.py` (`reactor_api`, `raw_world_bind`) |
| Name a DM-owned key | a number from `om_world_key_id()` | a string key | `api_lints.py` (`string_keys`), `check_grep.sh` |
| Run periodic work | a periodic lane (`PERIODIC_START(E, lane)`) or the machine pipeline, parked when idle (§4.10) | `process()`, `START_PROCESSING` | `pollers_lint.py` |
| Wait for a deadline | `om_after()` / `om_deadline()` | comparing `world.time` with a stored deadline in periodic work | `check_deadline_polling.py` |
| Remember an object | an OM handle, `om_handle(E)` / `om_resolve(h)` (§4.11) | `weakref` | `scheduler_lints.py` (`weakref`) |
| Hold an object reference | a relation or slot, an owned child, an OM handle, a declared cache (§4.11), `REF_DEF` for a frozen definition or registry object (implicit for `DEF_TYPES`), or `REF_TRANSIENT` on a pooled type; declared with the `REF_*` forms or one-place `REF_VAR` ([lifecycle.md §4](lifecycle.md#4-declared-references)) | an undeclared object-typed var; `REF_TRANSIENT` on a type that isn't pooled | `scheduler_lints.py` (`lc_refs`), `declared_refs_lint.py` |
| Reuse a scratch object on a hot path | `POOL_DECLARE(type)`, `pool_take(type)` / `obj.release()`, with its per-use fields declared `REF_TRANSIENT` ([lifecycle.md §4.1](lifecycle.md#41-one-place-declarations-and-pools)) | a hand-written `GLOB` free list and release proc that clears fields by hand | review |
| Delete something | a lifecycle verb (`code/datums/lifecycle/verbs.dm`): `consume()`, `replace_with()`, `expire()` or a lifetime, `slot_clear()`, `delete_on_death`; plain `qdel()` only when no verb fits | `del()`; a new `qdel()` where a verb fits | `scheduler_lints.py` (`del`), `lifecycle_counts_lint.py` (`qdel(` sites per file) |
| Keep a set of live instances | an OM registry (`REGISTRY_MEMBERS()`) | a `GLOB` list of instances; a list allocated per instance | `registry_lint.py`, `instance_list_lint.py` |
| React to something happening now | an OM event, `om_emit(E, new /datum/om/event/x)`; a `/datum/om/event/before/x` returning `EVENT_VETO` to refuse it (§10). Deferred or state-driven reactions use a channel, a watch or `om_after()` (§4.4, §4.11) | `RegisterSignal()`/`SEND_SIGNAL()`, `AddComponent()`, `AddElement()` outside the DCS core (`CORE` in `dcs_lints.py`) and sites marked `ALLOW(dcs)`; per-folder replacements in `signal_migration_map.md` | `dcs_lints.py` (`register_signal`, `add_component`, `add_element`) |
