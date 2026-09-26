# Object model framework: report

Branch `rewrite/om-pipeline` (on `rewrite/life-om`). This is the state of the object model (OM)
core after pipelines landed and Life and four machine types moved onto them. The reference is
`object_model_core.md`; Life's side is `life_on_om.md`; earlier numbers are in
`life_on_om_benchmark.md`.

## 1. What the framework is

Game code states **what** an entity does, **when** it runs and **what wakes it**. The core
owns the scheduling, sleeping, parking, change tracking, timers and cleanup. Everything is
declared in tables (decls, behaviours, stages, statuses) that are compiled once at boot, so
the per-tick cost is one dispatch per entity plus the work itself.

All of it is in `code/datums/om/` (about 10k lines with the standard library) and
`code/__defines/om.dm`.

## 2. Concepts

**Decls** (`/datum/om/decl`). A decl attaches things to types: `of` lists entity types,
`behaviours` lists what runs on them, `stages` adds pipeline stages, `watches` and `relations`
add the rest. A type's plan is built once from every decl that covers it.

**Behaviours** (`/datum/om/behaviour`). One kind of periodic or reactive work, such as upkeep,
a timer or a pipeline. Vars: `every` (cadence), `step_interval` and `max_catchup` (fixed
steps, with bounded catch-up), `lane`, `relevance`, `runlevels`, `requires` (checks that
must pass before it starts; they are checked again when their channels change), `min_interval`,
`wake_on`. The work goes in `run(E, dt)`. A behaviour with no cadence is reactive and runs
only when woken.

**Rings.** Cadence work runs on timing rings: one slot list per interval, spread across
ticks. An entity joins a ring at a slot, and the ring's `run_slot` calls the behaviour, or the
pipeline's `run_frame`, directly. Adding or removing an entity is O(1) (swap-remove with an
index).

**Lanes.** Budgets inside the behaviours subsystem: `LANE_SIMULATION`, `LANE_DERIVED`,
`LANE_PRESENTATION`, and so on. Each lane has a share of the tick. An over-budget lane stops
at the slot boundary and carries the rest over; breaches are counted.

**Pipelines and stages** (`pipeline.dm`). A pipeline is a behaviour that runs an ordered list
of stages over one shared frame. Stages are ordered by `after`/`before`, then `order`, then
path, and cycles are boot errors. A stage has `perform(E, F)`, which must not sleep; an
`idle(E)` rule; `wake_on` channels; an optional `run_if` over facts; an optional
`min_interval`; and a `rewake_delay`. Families and variants choose, per entity type, the
variant whose `of` is deepest. Plans are cached per type, and per entity when extras are
added. The runner checks one bit per stage: idle stages cost nothing, and an entity whose
stages have all been idle for `park_after` frames parks.

**Frames and facts.** A frame is the per-entity state of one pipeline: its plan, idle bits,
idle count, parking, extras, per-stage last run and facts. A frame type declares
`facts = list(name = list(compute proc, depends_on channels))`. A fact is computed lazily and
cached for the frame. `run_if` compiles to bit masks over facts. When a fact's channels are all
in a stage's wake mask, a failed `run_if` idles the stage instead of re-checking it every
frame. Nested runs (`om_stage_run_now`) take a scratch frame from `sched.free_frames`.

**Changes** (`om_changed(E, channels)`). The only wake signal. Channels are bits (for example
`CHANGE_MOB_STAT`, `CHANGE_MOB_EQUIPMENT`, `CHANGE_MACHINE_POWER`). A change clears the idle
bit of every stage whose `wake_on` includes it, unparks the entity, and re-checks any
`requires` that listen to it. Base setters raise the changes (`set_stat`, `forceMove`,
`power_change`, `atom_break`, equip and unequip, `add_mutation`, `set_species`, ...). The
pipeline audit finds a missed `om_changed`: in tests it is a failure.

**Contributions, effects, statuses, immunities** (`contribution.dm`, `status.dm`). A value
such as a speed modifier or a flag set is the combination of named contributions from its
sources. Removing a source removes its contribution, so there is no "undo" code. A status is a
contribution with a clock: `duration`, `stacks`, `min_interval` ticks, and `on_apply` and
`on_expire` hooks. Timed statuses expire on deadlines, not by polling. An immunity blocks a
status or an effect at the point of application. Godmode is an effect that other code reads
through `om_has_effect`.

**Relations** (`relation.dm`). Typed links between entities (holder/held, buckled, grabbed,
host/parasite) that have their own cleanup: when either end is deleted or moves out of range,
the relation ends and both sides are told. This replaces hand-rolled weakref lists and
`Destroy()` cleanup.

**Events and checks** (`event.dm`, `check.dm`, `check_library.dm`). Checks are small
reusable predicates (`alive`, `conscious`, `in_range`, `target_exists`, `has_client`, ...)
combined with `ALL_OF`, `ANY_OF` and `NOT_OF`. Each check declares the channels that can
change its answer, so a `requires` list knows when it needs re-checking. Events are typed
broadcasts with subscribers held by relations.

**Tasks** (`task.dm`). Timed actions (the replacement for `do_after` plus `sleep`):
`om_task_start(actor, def, target)` returns the task, or a reason string when it can't
start. A task def gives `duration`, `claims` (one task per target per claim: no double
start), `requires` checks (checked again on their channels; a failure cancels the task),
`complete_proc` and `cancel_proc`. Death and deletion cancel through the checks and the
relation to the actor. Nothing sleeps.

**UI binds** (`ui.dm`). A bound UI field is a derived value with channels: the UI refreshes
when a channel it reads changes, not every tick.

**Clocks** (`deadline.dm`). `om_after(E, delay, owner, key)` makes deadlines keyed by entity,
owner and key. Scheduling the same key again replaces the old deadline. They are stored in a
timing wheel. Stage rewakes, status expiry, task completion and `min_interval` throttling all
use them. The world clock and a mob's own clock (stasis slows it) are separate: Life reads
`F.dt` from the mob's clock.

**Relevance and parking.** A behaviour's `relevance` maps relevance levels (for example, a z
level with players, with none, or no z at all) to run, slow or park. Relevance changes when an
entity changes z: `Moved()` calls `onTransitZ` → `life_update_relevance`. All mob `loc` writes
now go through `forceMove()`/`moveToNullspace()`, so relevance can't miss a move. Parking
takes the entity off the ring into the scheduler's parked list, where it costs nothing. A
change or rewake unparks it.

## 3. Before and after

### Life

Before (`rewrite/life-om`): a hand-written frame loop on the mob, `life_frame()`, 612 lines of
`life_om.dm` with its own composition cache, sleep bits, shared scratch list,
"frames don't nest but may sleep" workaround, profiling branch and hibernation list:

```dm
/mob/living/proc/life_frame(profile = FALSE)
	set waitfor = FALSE
	var/datum/life_composition/comp = life_composition || recompose_life()
	var/datum/life_context/ctx = life_ctx
	...
	var/static/list/scratch = list()
	var/static/scratch_busy = FALSE
	...
	for(var/i in 1 to length(ordered))
		var/datum/life_system/S = ordered[i]
		if(S.wake_only && (S.wake_only == LIFE_WAKE_ONLY_DERIVE || has_client))
			continue
		if(life_asleep_total && (bits[LIFE_ASLEEP_WORD(i)] & LIFE_ASLEEP_BIT(i)))
			continue
		...
```

After: `life_om.dm` is 212 lines of declarations. The loop, sleeping, parking, catch-up,
profiling and nesting all belong to the core:

```dm
/datum/om/pipeline/life
	name = "life"
	every = LIFE_CYCLE
	step_interval = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	relevance = list(OM_PARK, null, null, null)
	stages = list(/datum/om/stage/life)
	frame_type = /datum/om/frame/life
	wake_all = LIFE_WAKE_ALL
	park_after = LIFE_PARK_AFTER

/datum/om/stage/life/mutations
	order = LIFE_PHASE_INPUT + 100
	name = "mutations"
	wake_on = CHANGE_MOB_STATUS
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/// The root only feeds its signal's listeners.
/datum/om/stage/life/mutations/idle(mob/living/self)
	return type == /datum/om/stage/life/mutations && !self._listen_lookup?[COMSIG_HANDLE_MUTATIONS]
```

The 38 Life families (breathing, blood, chemicals, environment, organs, vision, NPC and so on)
are stages. Species and mob types provide variants (`of = /mob/living/carbon/human`).

### A machine: the recharger

Before: the recharger polled on SSmachines every 2 s. It returned `PROCESS_KILL` when it had
nothing to do, and every wake that followed paid one more poll just to kill itself again:

```dm
/obj/machinery/recharger/process()
	if(stat & (NOPOWER|BROKEN) || !anchored)
		update_use_power(USE_POWER_OFF)
		icon_state = icon_state_idle
		return PROCESS_KILL
	if(!charging)
		update_use_power(USE_POWER_IDLE)
		icon_state = icon_state_idle
		return PROCESS_KILL
	...
```

After: a variant of the machine pipeline's `power` stage. Facts (`powered`, `broken`,
`anchored`) come from the frame. The idle rule says when it is settled. Inserting or removing
an item raises `CHANGE_MACHINE_OCCUPANT`. A settled recharger parks, costs nothing, and
wakes on the change:

```dm
/datum/om/stage/machine/power/recharger
	of = /obj/machinery/recharger

/datum/om/stage/machine/power/recharger/perform(obj/machinery/recharger/M, datum/om/frame/machine/F)
	if(!F.usable())
		M.update_use_power(USE_POWER_OFF)
		M.icon_state = M.icon_state_idle
		return STAGE_IDLE
	...
	M.charge_step()

/datum/om/stage/machine/power/recharger/idle(obj/machinery/recharger/M)
	if((M.stat & (NOPOWER | BROKEN)) || !M.anchored)
		return M.use_power == USE_POWER_OFF
	if(!M.charging || M.charging_complete())
		return M.use_power == USE_POWER_IDLE
	return FALSE
```

### Timed mob work: the spider nurse

Before: the stage called `INVOKE_ASYNC(self, .../web_tile, loc)`, which ran
`do_after(src, 5 SECONDS)` and could start twice if two Life frames overlapped the wait.
After: `web_tile()` starts `/datum/om/task_def/mob_work/spider_web` (5 s, claims the turf,
requires the mob to be conscious and in range and the target to exist) and returns at once.
`web_done()` or `work_interrupted()` finishes the work.

## 4. Migrated and not migrated

| Area | State |
|---|---|
| Life, every `/mob/living` | on pipelines: `life` (38 families), `life_derive` (canmove), `life_present` (HUD, client only), `life_vision` (sight for every mob, reactive) |
| Ghosts, AI eyes, blob overmind | `observer_upkeep` behaviour |
| Recharger, cell charger, APC, SMES | machine pipeline (`power` + `present` stages) |
| Timed statuses, godmode, immunities | contributions/statuses |
| Spider webs and eggs, ant building, stealth-mouse cloak | om tasks |
| Leech feeding from Life | direct, non-sleeping (`feed_on_random_organ`) |
| Mob `loc` writes | `forceMove`/`moveToNullspace` (44 sites); 3 direct writes left that call `onTransitZ` themselves |
| Every other SSmachines machine | not migrated: still polls (with the older hibernation work) |
| SSprocessing objects, SSobj, atmos, power nets | not migrated |
| Speech/emote from stages (fish, dragons, secbot, cats, dogs, clockwork, snake, slime nutrition, borer brain damage) | still `INVOKE_ASYNC`: `say()` can sleep deep in the chat path, and making it non-sleeping is not cheap. Their return values are unused. |
| AI movement from stages (chase, succlet, secbot attack), shadekin ability, `nif.life` | still `INVOKE_ASYNC`, by design |
| `do_after` in player verbs | not migrated (tasks exist; verbs are a later slice) |

## 5. Performance

One benchmark after all the work: `life_sweep,om_dispatch`, 3 counted boots per side after a
warm-up, `--arg=seconds=30 -DLIFE_CYCLE_DS=20 -DLIFE_NO_PROFILE -DOM_NO_STAGE_PROFILE`, sides run
one after the other. Base is `rewrite/life-om` 7f9640613e (Life's hand-written loop); new is
f295901848. Medians of 3.

| metric | base | new | new / base |
|---|---|---|---|
| h128 Life us per frame | 2121 | 1897 | 0.89 |
| h128 tick avg / p95 / p99 (% of tick) | 26.2 / 76 / 117 | 15.8 / 22 / 27 | |
| h128 overruns | 19 | 0 | |
| h128 frames delivered | 1956 | 1922 | 0.98 |
| mix Life us per frame | 1272 | 1282 | 1.01 |
| mix tick p95 / p99 | 17 / 21 | 17 / 21 | |
| mix parked mobs | 384 | 384 | |
| machines ms per s (h128 / mix) | 0.68 / 0.49 | 0.61 / 0.53 | |
| reference loop (`om_dispatch_process_ns_per_call`, same code both sides) | 1345 ns | 1061 ns | 0.79 |

The machine ran faster during the new side: the reference loop, which is identical code on
both sides, was 21% quicker. Normalised by it, h128 Life per frame is about 1.13x base and mix
about 1.28x. The raw numbers show no regression, and the h128 tick tail is far lower (p99
27 vs 117 %; the base side had 19 overruns). The truth is between those two readings: the
runner costs slightly more per frame than the hand loop did, and the core's lane budgeting
keeps the tick smoother.

`om_dispatch` pipeline micro-benchmark: 5000 entities, 8 stages, against a hand frame loop
over 8 flyweights with an idle rule each.

| per entity | hand loop | runner called directly | runner from the ring |
|---|---|---|---|
| all 8 awake | 9.9 us | 16.9 us | 18.4 us |
| 7 of 8 idle | 3.0 us | 5.7 us | 7.6 us |

Solving the two rows: the runner adds about **0.6 us per awake stage** (target 0.8: met) and
about **2.1 us fixed per entity frame** when called directly (target 2: at the limit), with the
ring adding about 2 us more. Idle stages cost nothing. Earlier runs on this branch, before the
per-entity frame and the local-count work, measured 6 us fixed and 1.7 us per stage.

Tests: the full suite passes, 1111 passed and 0 failed. DreamChecker reports 16 errors on the
branch against 22 on base, and none of them come from stages.

## 6. Known limitations

- **Runner overhead.** Each awake stage costs a proc call plus an `idle()` call. An entity
  frame has a fixed cost (frame vars, facts reset, counters, park check). In DM, every local
  and every datum var read costs, so the runner uses macros with few locals, but it still
  sits above a hand loop in the micro-benchmark. Life cost is set by stage bodies, so it
  doesn't show up in the macro numbers.
- **Async speech.** Stages that talk still fork a thread per call. They are rare, but they
  are the only sleeping work left under a stage.
- **Timing-sensitive tests.** A few reactor and cadence tests count ticks and can fail on a
  loaded machine. They are unaffected by this work but show up as noise.
- **Audit sampling.** The missed-wake audit samples entities; it isn't exhaustive, so a rare
  missed `om_changed` can slip through outside tests.
- **Machines.** Only four types use the pipeline, so SSmachines still exists and still costs
  its roster walk.
- **Direct `loc` writes.** Anyone who writes `loc =` on a mob again bypasses relevance. A
  lint (DreamChecker rule or grep in CI) would close this.

## 7. Next migration slices

1. **Remaining SSmachines polling types** onto the machine pipeline, one family per slice
   (atmos devices with reactor watches first, then consoles). After the last one, retire
   SSmachines' roster.
2. **`do_after` in verbs** → om tasks with claims (surgery, construction, cuffs), with a
   progress-bar UI bind.
3. **Non-sleeping `say`/`emote`** for NPCs, so stages can drop the last `INVOKE_ASYNC`.
4. **SSprocessing objects** (items with `process()`) onto behaviours with idle rules.
5. **Lint for `loc =` on movables** and for `sleep`/`do_after` reachable from `perform()`.
6. **Runner cost:** code-generate one `run_frame` per plan shape (no per-stage `gated` test on
   plans with no gated stage), and merge `idle()` into `perform()`'s return for stages whose
   idle rule is their own early return.
