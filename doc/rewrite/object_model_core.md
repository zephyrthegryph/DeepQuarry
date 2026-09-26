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
`SUM_OF`, `CHECK`), `scheduler_advance` and `AWAIT`. `ALL` was already a
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
| Task | a row in a `tasks` table, or `/datum/om/task_def/<x>` |
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
- **Relations:** `contained_in`, `worn_by`, `occupant_of`, `buckled_to`
  (gives `EFFECT_BUCKLED`), `stasis_occupant` (stops the occupant's
  biological clock while the bed is powered), `powered_by`, `claim`.
- **Bundles:** `powered_machine`, `storage`, `occupant_seat`,
  `powered_vehicle`, `stasis`, `hud_on_vitals`, `ui_live`.
- **Tasks:** `/datum/om/task_def/timed_tool` (params `tool`, `duration`).

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

- `om_after(E, delay, B, sub = 0)` calls `B.on_deadline(E)` after `delay`
  deciseconds. One deadline per (entity, behaviour, sub-key); calling again
  replaces it. `om_cancel_after(E, B, sub)`, `om_cancel_all_after(E, B)`,
  `om_deadline_pending(E, B, sub)`. The key is `bid + sub * OM_DL_SUB`, so firing
  one decodes it with no search: sub 0 is `on_deadline`, `OM_DL_THROTTLE` a
  `min_interval` wake, `OM_DL_STAGE + n` a pipeline stage's rewake
  (`on_keyed_deadline`).
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
`om_clock_rate_of(E, CLOCK_X)` reads it.

### 4.7 Relevance

`RELEVANCE_NONE`, `NEAR`, `VISIBLE`, `WATCHED`. An entity's level is the
largest `EFFECT_RELEVANCE` contribution: `om_observe(E, observer, level)`,
released when the observer goes. `OM_PARK` in a behaviour's `relevance` list parks
it at that level (Life: `list(OM_PARK, null, null, null)`, so a low-priority mob on a
z-level without players costs nothing and nothing is tested per frame). `om_ui_bind()` holds `WATCHED`. A level
change moves the entity between rings and calls
`om_native_bridge_relevance(E, level)`.

### 4.8 Native (Rust) watches

`wake_on_native` bits are unioned per entity and passed to
`om_native_bridge_watch(E, bits)` on attach and detach. The reactor's drain
calls `om_native_deliver(E, bits)`, which runs `on_native(E, bits)` on each
started behaviour declaring those bits. The two `om_native_bridge_*` procs
are stubs today; the reactor track replaces their bodies with generated
bindings. Nothing else in this API crosses the FFI.

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
  same relation, so a slot gets everything above for free (view fields,
  `changes` channels, contributes/grants) on top of capacity, exposure and
  propagation. A slot decl declares `holder` (a type, or list of types)
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
- **Checks:** `/datum/om/check/x/why_not(actor, target)` returns null or a
  reason; `depends_on` lists the channels that can flip it; `arg` is the
  parameter. `om_why_not(spec, actor, target)`, `om_can(...)`,
  `om_check_get(spec)`.

## 11. Tasks and UI (sections I, J)

- `om_task_start(actor, name_or_type, target, params)` returns the task or a
  reason. It checks `requires`, claims the target (a `target_single`,
  refusing claim relation: the loser gets "is in use"), and sets one
  deadline. It completes by that deadline, and is cancelled when its
  requires fail (re-checked on their channels on actor or target), when an
  `interrupted_by` event reaches the actor, or when either end is deleted.
  `on_complete` / `on_cancel` run once. Nothing polls.
- `AWAIT(task, timeout)` is for legacy procs that must sleep; the timeout is
  mandatory and a missing one is an error.
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
| Waits without timeouts | `AWAIT` needs one; tasks end by deadline |
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
