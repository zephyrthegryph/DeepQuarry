# Mob Life on the object-model core

Status: **implemented on `rewrite/om-pipeline`** (first on `rewrite/life-om` as a Life-specific
frame loop; that loop is now the core's pipeline runner). Builds on
[object_model_core.md](object_model_core.md) (the API; pipelines are §4.10, timed statuses §8.1)
and replaces the scheduling half of [../mob_life_architecture.md](../mob_life_architecture.md)
§4.3 and §4.8-4.9. Life is declarations and stage bodies: three pipelines, a frame whose facts
are the old gates, and the stages (the old life systems, families and variants). Everything
that decides **when** a stage runs belongs to the core.

Benchmark results: [life_on_om_benchmark.md](life_on_om_benchmark.md).

## 1. What is replaced

| Old (deleted) | New |
|---|---|
| `SSmobs.fire()` walking `GLOB.mob_list` in 8 shrinking slices | the `life` pipeline's cadence ring |
| `/mob/living/Life(seconds, profile)`, then `life_frame()` | the core pipeline runner, one dispatch per mob |
| `/datum/life_system` flyweights, `tick()`, compositions | `/datum/om/stage/life` stages, `perform()`, plans (per mob type and extras) |
| gates, segments, `ctx.blocked`, `no_sleep` | frame facts (`placed`, `alive`, `status_ok`, `in_stasis`, `environment`) and `run_if` |
| `LIFE_HALT` | `ctx.abort()` |
| `LIFE_PHASE_*` plus `order` | one `order` (`LIFE_PHASE_BODY + 90`); `after`/`before` for new stages |
| `life_awake` bits, `LIFE_SYS_*`, `LIFE_WAKE_*` groups, then `LIFE_WAKE_ON_*` | per-stage `wake_on` masks of `CHANGE_MOB_*` channels; `LIFE_WAKE_ALL` is the pipeline's `wake_all` |
| `life_wake(bits, reason)` in producers | `om_changed(L, CHANGE_MOB_*)` |
| hibernation (`life_hibernate()`, `life_resume()`, `GLOB.life_hibernating_mobs`, `life_idle_frames`) | parking, owned by the core (`park_after` 2, the scheduler's parked list) |
| `life_wake_in()` and its `addtimer`, then `life_timers` | stage rewakes: core deadlines keyed by (mob, pipeline, stage) |
| the low-priority z-level test in every frame, the runlevel test in every frame | relevance `OM_PARK` with z-level presence holds (§11), pipeline `runlevels` |
| variant choice by the string length of `mob_type` | `of`, resolved by inheritance depth once per plan |
| the `life_present` hand-written throttle | the pipeline's `min_interval` |
| the hibernation audit in SSmobs | the core pipeline audit (SSbehaviours) |
| `life_last_time` and `seconds` | the ring's dt; content per cycle runs as fixed steps |
| `period` (every Nth cycle) | unused; deleted |
| `body.advance_stasis()` fractional counter over `BF_STASIS` | `CLOCK_BIO` local time; stasis sources hold `EFFECT_CLOCK_BIO_INHIBIT` |
| `mob.enabled` (absorbed prey, TF holder) | `om_suspend(mob, source)` |
| every status counter Life decremented (`stunned`, `weakened`, `paralysis`, `sleeping`, `confused`, `eye_blind`, `eye_blurry`, `ear_deaf`, `stuttering`, `silent`, `druggy`, `slurring`, `drowsyness`, `hallucination`, the dizzy and jittery components' counters) | timed statuses in the contribution store (`EFFECT_*`, §7), set with `status_at_least()`/`status_set()`/`status_adjust()` |
| `Stun()`, `Sleeping()`, `SetConfused()`, `AdjustBlinded()`, `make_dizzy()`, `get_stunned()`, `is_paralysed()` and friends, `on_status_counter_changed()` | the status API (§7); the named setters are deleted |
| the `statuses` family (and its AI, pAI, robot and simple mob variants) | nothing: statuses end by deadline and their alerts follow the effect |
| `CANSTUN`, `CANWEAKEN`, `CANPARALYSE` status flags | immunity effects `EFFECT_IMMUNE_*` (§7.3) |
| the `GODMODE` status flag and `COMSIG_CHECK_FOR_GODMODE` | `EFFECT_GODMODE`, held by the godmode element; it implies the incapacitation immunities |
| `toggled_sleeping` | a `"voluntary"` hold on `EFFECT_SLEEPING` |
| `ctx.living_result`, `ctx.core_result` (old `Life()` return values) | `ctx.fact("alive")` |
| per-mob `Life()` on observers, AI eyes, blob overmind via SSmobs | `observer_upkeep` behaviour on `/mob/observer` |
| MOB_PROFILE sampling on SSmobs | per-pipeline cost from `om_diagnostics()`, plus the core stage profiler (every 16th frame) |

SSmobs remains only as the home of death reporting (`report_death()`, `death_list`) and the
two-minute profile and parking summaries. It runs no Life.

## 2. Three pipelines

`/datum/om/decl/living` attaches three pipelines to every `/mob/living`
(`code/modules/mob/living/life/life_om.dm`):

| Pipeline | Cadence | Stages | Notes |
|---|---|---|---|
| `life` | one frame per `LIFE_CYCLE`, fixed steps, catch-up 2 | the frame: every family under `/datum/om/stage/life` whose `pipeline` is `life` | parks when every stage is idle; `runlevels` game and postgame; relevance NONE parks |
| `life_derive` | none (reactive), `LANE_DERIVED` | `canmove` | runs the pass a status or the stat changes |
| `life_present` | none (reactive), `LANE_PRESENTATION`, `min_interval` 0.5 s | `hud`, `vision`, `hud_refresh` | `requires` a client; starts by running its stages once |

Plus `observer_upkeep` (a behaviour, `runlevels` game and postgame) for ghosts, AI eyes and the
blob overmind.

Why one frame pipeline and not a behaviour per family: the stages share one frame (its facts,
the stasis step), a deferral must never split a frame across ticks, and fifty ring entries per
mob would be fifty dispatches where the runner makes one. A stage is a flyweight, so the 571
variant types cost nothing per mob.

**Stages.** `perform(self, ctx)` is the old `tick()`. `idle(self)` is the idle rule, `wake_on`
the channels that wake it, `rewake_delay(self)` a slow drift, `run_if` its facts. A family
root's `of` is `/mob/living`; a variant's `of` names the mob type it serves, and the plan takes
the deepest one in the mob's inheritance. `life_sets` (read by `applies()`) keeps the silicon
sequences apart, and trait stages are `extra` (a component adds its own with `om_stage_add()`).

## 3. Cadence and balance (the decision)

### 3.1 What the old scheduler actually did

`SSmobs` fired every 0.25 s and meant to cover every mob once per 2 s in 8
slices. Each fire took `ceil(remaining / 8)` mobs from the run list, where
*remaining* shrank as the cycle went on. The quota shrank with it, so a cycle
took far more than 8 fires. `GLOB.mob_list` holds every mob (lobby players,
observers, hibernating mobs, which are skipped but still counted):

| mobs in `GLOB.mob_list` | fires per cycle | real cycle | vs. the intended 2 s |
|---|---|---|---|
| 8 | 8 | 2.0 s | 1.0x |
| 32 | 16 | 4.0 s | 2.0x slower |
| 64 | 21 | 5.25 s | 2.6x |
| 100 | 24 | 6.0 s | 3.0x |
| 128 | 26 | 6.5 s | 3.25x |
| 200 | 29 | 7.25 s | 3.6x |
| 512 | 36 | 9.0 s | 4.5x |

(`tools`-free check: simulate `rem -= ceil(rem/8)` until 0.) A lone mob ran
every 0.25 s, eight times faster than intended. Southern Cross maps 19 mobs;
players, lobby mobs, observers and expedition site populations bring a
normal round to 60-150, so players have lived with a **5-6.5 s** cycle.

Every life system except physiology is written *per cycle*: stun counters
drop by one per cycle, hunger by a fixed amount, organs process once,
diseases advance one stage roll. Only `physiology` scales by the elapsed
`seconds`. So the per-real-second balance players experienced was set by
the buggy cadence, and it varied with population.

### 3.2 Decision

- **The Life cycle is 6 s of real time, fixed** (`LIFE_CYCLE`, one define in
  `code/__defines/life_systems.dm`). This keeps per-cycle content at the
  per-second rates players actually had at a typical population (about 100
  mobs), instead of silently speeding hunger, bleeding, healing, disease and
  organ decay up 3x, which is what "fixing" the quota to a true 2 s cycle
  would do. What is removed is the *variance*: the rate no longer depends on
  how many mobs exist. A small test round (8 mobs) now runs Life 3x slower
  than before, a 500-mob round 1.5x faster; both converge on the typical
  round.
- **Per-cycle content runs as fixed steps** (`step_interval = LIFE_CYCLE`):
  `on_step` runs one frame per 6 s of elapsed (clock) time. **Catch-up is
  capped at 2 frames per tick** (`max_catchup = 2`); beyond that the missed
  frames are dropped and counted as breaches in `om_diagnostics()`. The old
  scheduler never caught up (a late mob just ran one frame late), so the cap
  only bounds how much a hitch can bunch up.
- **dt-scaled content** (physiology) gets `LIFE_CYCLE` seconds per frame,
  which is what a frame covers.
- **Statuses** (§7) convert one old counter unit to `LIFE_CYCLE` seconds, so
  a two-unit stun lasts 12 s as `Stun(2)` did at a typical population.
- Anything that wants a different rate retunes one number. A later balance
  pass can move content to dt and shorten the cycle; this change does not
  mix a balance pass into a scheduler migration.

Tests and benchmarks may compile a different cycle (`-DLIFE_CYCLE_DS=20`);
the benchmark uses 2 s on both sides so both schedulers deliver the same
number of frames (§11, and the benchmark doc).

## 4. Per-frame semantics

The core runner (object_model_core.md §4.10) runs a frame:

1. Take a frame from the pool; `begin()` advances the stasis counter once (§8).
2. Run the plan in order. Skip a stage that is idle, or whose `run_if` fails. A skipped stage
   idles when a channel in its wake mask reports what blocked it (`alive` has
   `CHANGE_MOB_STAT`, every Life stage wakes on it), or when its `idle()` holds.
3. After a stage runs, it idles if it returned `STAGE_IDLE` or its `idle()` holds; its
   `rewake_delay()` becomes a keyed deadline.
4. Stop at once if a stage deleted the mob, changed its plan, or called `ctx.abort()`
   (`OM_ABORT_FRAME`: nothing idles this frame, the old early return before `..()`).
5. After the frame, if every stage is idle, the frame counts as idle; after `LIFE_PARK_AFTER`
   (2) idle frames in a row the mob parks.

The old gates are facts:

| Fact | Computed | Reported by | Was |
|---|---|---|---|
| `placed` | `loc && !transforming` | nothing (transforming raises no channel) | `gate/transforming`, `gate/placed` (`LIFE_SEG_LIVING`) |
| `alive` | `stat != DEAD`, read again after the status stage | `CHANGE_MOB_STAT` | `gate/alive`, the simple mob vitals gate |
| `status_ok` | set by the status stage (`update_status()`'s result) | `CHANGE_MOB_STAT` | `LIFE_SEG_LIVING_STATUS` |
| `in_stasis` | the frame's stasis step | nothing (a fractional counter) | `ctx.in_stasis()`, `gate/human_vitals` |
| `environment` | the turf or belly air | `CHANGE_MOB_LOC` | `ctx.environment` |

`run_if` shorthands: `LIFE_RUN_IF_PLACED`, `LIFE_RUN_IF_PLACED_ALIVE`, `LIFE_RUN_IF_STATUS_OK`,
`LIFE_RUN_IF_LIVE_BIOLOGY` and `LIFE_RUN_IF_DEAD_BIOLOGY` (the human tail inside and outside
`stat != DEAD`, never in stasis).

Nothing is tested per frame for the lobby or for player-free z-levels: the ring is dormant
outside the pipeline's `runlevels`, and a low-priority mob on a z-level with no living player is
at relevance NONE, where the pipeline parks (§11).

## 5. Idle, wake, parking and rewakes

**What wakes a stage.** Each stage declares `wake_on`, a mask of mob channels; the pipeline's
`wake_all` (`LIFE_WAKE_ALL`: `CHANGE_MOB_STAT`, `CHANGE_MOB_CLIENT`, `CHANGE_EXPLICIT`) wakes
every stage. Producers raise channels with `om_changed()`:

| Channel | Raised by |
|---|---|
| `CHANGE_MOB_HEALTH` | `injure()`, `mend()`, `fully_heal()`, `body.invalidate()` |
| `CHANGE_MOB_STATUS` | a status starting or ending (§7), immunities, pulling |
| `CHANGE_MOB_LOC` | `/mob/living/Moved()` |
| `CHANGE_MOB_EQUIPMENT` | equip and unequip |
| `CHANGE_MOB_CONDITIONS` | modifiers, instability, diseases |
| `CHANGE_MOB_STAT` | `set_stat()` |
| `CHANGE_MOB_CLIENT` | Login, Logout |
| `CHANGE_EXPLICIT` | `om_wake()`, a plan change, the audit |

A wake clears the idle bit of every stage whose wake mask matches; it never runs a frame (the
next cadence frame runs the woken stages). A change raised during a frame is delivered after
it, so a stage that idled at the end of the frame is woken right back.

**Parking** is the core's: after two idle frames in a row the mob leaves the ring and joins the
scheduler's parked list for the pipeline; any wake unparks it and wakes every stage, so each
re-checks its rule. The first frame after a nap covers at most one cycle: the ring never hands
a rejoining entity the length of its nap.

**Rewakes.** `rewake_delay()` (darksight, AFK, ambience, air drifting in place) becomes a
deadline keyed by (mob, pipeline, stage). It wakes that stage only; a parked mob comes back for
it counting one idle frame already, so it parks again as soon as the stage idles.

**Audit.** The core pipeline audit (SSbehaviours, every 30 s in test and TESTING builds, or with
the `OM_PIPELINE_AUDIT` config flag or the "Toggle Pipeline Audit" verb) samples parked mobs and
awake mobs with idle stages and asks every idle stage without a pending rewake whose `run_if`
passes whether its rule still holds. A rule that doesn't is a missed `om_changed()`: logged
(`OM_AUDIT: MISSED WAKE`), a failed test in unit tests, and the mob woken.

## 6. The derive and present pipelines

- `life_derive` runs `canmove` the pass a status or the stat changes, never on a cadence. Stun,
  weaken, paralysis and sleep also update `canmove` and lying at once through their status
  hooks (§7).
- `life_present` runs `hud`, `vision` and `hud_refresh` for a mob with a client: on their
  channels, at most every `LIFE_PRESENT_MIN_INTERVAL` (0.5 s; a walking player raises a location
  change most ticks and the HUD needs only the latest state: wakes in between coalesce and
  arrive by one deadline), by their rewakes (darksight 5 s, HUD refresh 1 min) and, while one
  still has work, every `busy_retry` (one cycle). Login raises `CHANGE_MOB_CLIENT`, which
  re-checks the requirement and starts it. A clientless mob never starts it.
- `refresh_hud()`, `refresh_vision()`, `refresh_glow()`, `process_chemicals()` run a stage on
  demand (`om_stage_run_now()`, with its own frame).

## 7. Statuses as contributions

Every timed impairment is a contribution the mob holds on itself in the contribution store,
ended by the deadline wheel. Nothing counts a status down per frame, so a running status costs
nothing until it starts or ends, and Life never wakes itself by decrementing its own counters.
Code: `code/modules/mob/living/life/statuses.dm` (definitions and API), rows in
`om_library_effects()`.

### 7.1 The statuses

| Was | Effect | Units worn off per `LIFE_CYCLE` |
|---|---|---|
| `stunned` (`Stun()`) | `EFFECT_STUNNED` | 1 |
| `weakened` (`Weaken()`) | `EFFECT_WEAKENED` | 1 |
| `paralysis` (`Paralyse()`) | `EFFECT_PARALYZED` | 1 |
| `sleeping` (`Sleeping()`) | `EFFECT_SLEEPING` | 1; carbons: the species' `waking_speed` |
| `confused` (`Confuse()`) | `EFFECT_CONFUSED` | 1 |
| `eye_blind` (`Blind()`) | `EFFECT_BLINDED` | 1 |
| `eye_blurry` | `EFFECT_BLURRY` | 1; 4 while a human wears a blindfold |
| `ear_deaf` | `EFFECT_DEAFENED` | 1 |
| `stuttering` | `EFFECT_STUTTERING` | 1 |
| `silent` | `EFFECT_MUTED` | 1 |
| `druggy` | `EFFECT_DRUGGED` | 1 |
| `slurring` | `EFFECT_SLURRING` | 1 |
| `drowsyness` | `EFFECT_DROWSY` | 1 |
| `hallucination` | `EFFECT_HALLUCINATING` | 2 |
| dizzy component's `dizziness` (`make_dizzy()`) | `EFFECT_DIZZY`, capped at 1000 | 3; 15 while resting |
| jittery component's `jitteriness` (`make_jittery()`) | `EFFECT_JITTERY`, capped at 1000 | 3; 15 while resting |

One unit is what the old frame took off per cycle, so every duration is what it was at a
typical population (§3): `Stun(2)` lasted two cycles and `status_at_least(EFFECT_STUNNED, 2)`
lasts 12 s. A status whose rate can change while it runs (resting, a blindfold) records the
rate its expiry was computed with; `status_rate_check()` rescales what is left when the rate
changes, so the same number of units remains (the shake components check on resting changes,
humans on equipment changes).

### 7.2 The API

| Old | New |
|---|---|
| `Stun(n)`, `Sleeping(n)`, `x = max(x, n)` | `status_at_least(id, n)`: never shortens |
| `SetStunned(n)`, `x = n` | `status_set(id, n)`: exactly n from now; 0 ends the mob's own dose |
| `AdjustStunned(n)`, `x += n`, `make_dizzy(n)` | `status_adjust(id, n)`: negative shortens, never below now |
| `clear_dizzy()` | `status_end(id)` |
| `if(M.sleeping)`, `is_stunned()` | `has_status(id)` (any source) |
| `M.confused > 5`, `get_stunned()`, `get_dizzy()` | `status_units(id)`: remaining timed units, rounded up (a hold has none: use `has_status()`) |
| | `status_remaining(id)` in deciseconds, `status_seconds(id)` for readouts |

The statuses are core timed statuses (object_model_core.md §8.1): the API is on `/datum` and
each row in `om_library_effects()` declares everything about its status. Increases
(`status_at_least()`, a positive `status_adjust()` or `status_set()`) are admitted first: a
held immunity blocks them (§7.3), then the row's `signal` (`COMSIG_LIVING_STATUS_STUN`,
`_WEAKEN`, `_PARALYZE`, `_SLEEP`, `_BLIND`, sent with the amount only and only for increases)
may veto them with `COMPONENT_NO_STUN`. Admitted increases of a `scaled` status go through
`status_scale()`: `BF_DISABLE_DURATION`, and a human's species `stun_mod`/`weaken_mod`.
Decreases are never blocked or scaled.

Each row declares what the old setters and the statuses system did by hand: its immunity, its
screen alert and status indicator (applied by `status_shown()`), and its hooks: `on_increase`
(`status_clear_facing`), `on_start` and `on_end` (`status_incapacitation_changed` re-derives
`canmove`; `status_knocked_down` also stops aiming; `status_passed_out` hands a rig to its AI;
the dizzy and jittery shake components and the deafness ear-ringing; a robot's sensors when
blindness ends). Nothing switches on which status it is. The channel
(`CHANGE_MOB_STATUS`) is raised once, by the effect, and only when the value changes: extending
or shortening a running status raises nothing, where the old setters raised the channel on
every call and the stun setters raised it twice.

**Holds instead of per-frame writes.** A condition that keeps a status on holds it with its own
key, or tops it up with `status_at_least()` in the frame that checks the condition (never a
decrement):
- Voluntary sleep (the Sleep verb) is a `"voluntary"` hold on `EFFECT_SLEEPING`
  (`set_voluntary_sleep()`): no dose wearing off or ending wakes the mob, choosing to wake
  does. `toggled_sleeping` is gone.
- An unattended body (no client, or no mind) stays asleep: the human and alien frames top the
  sleep up to one unit while nobody is home, as the old frames stopped counting it down.
- A blindness or deafness disability, unconsciousness, a missing or broken eye and earmuffs
  top the matching status up, as the old frames set the counters every cycle.

Intentional differences, all small:
- A status ends at its exact time rather than at the next frame boundary (up to one cycle
  sooner), and it counts down while the mob is dead or transforming.
- Alerts, indicators and `canmove` follow the status the moment it starts or ends. Indicators
  used to be removed only by a setter reaching zero, so an expired stun left its icon up.
- A bruised eye keeps sight blurred (the comment said "permablurry"; the old code set blur to 1
  and then took it off in the same frame, clearing any blur instead).
- A client returning to a sleeping body wakes it when its dose is spent, rather than sleeping
  out up to three more cycles.

### 7.3 Immunity

`CANSTUN`, `CANWEAKEN` and `CANPARALYSE` are gone. Immunity is an effect in the contribution
store: `EFFECT_IMMUNE_STUN`, `EFFECT_IMMUNE_WEAKEN`, `EFFECT_IMMUNE_PARALYZE`,
`EFFECT_IMMUNE_DIZZY`, `EFFECT_IMMUNE_JITTER`. A status definition names the immunity that
blocks it; admission checks it; gaining the immunity ends every active status that names it
(`/datum/om/effect/mob_immunity`). Sources:

| Source | How |
|---|---|
| mob types that had the flags cleared (leeches, borers, space worms, armalis, eclipse mechs, cultists, mercs, constructs, the morph, test dummies, ...) | one multi-type decl, `/datum/om/decl/immune_incapacitation` (`of = list(...)`, `self_effects`) |
| the AI (could be stunned and paralysed, never weakened) | decl, `EFFECT_IMMUNE_WEAKEN` |
| silicons (their `make_dizzy()`/`make_jittery()` did nothing) | decl, `EFFECT_IMMUNE_DIZZY`, `EFFECT_IMMUNE_JITTER` |
| the hulk mutation (human `Stun()`/`Weaken()`/`Paralyse()` returned early) | `GLOB.mutation_immunities`, held by `add_mutation()`, released by `remove_mutation()` |
| godmode (admin, soulstones, AI eyes, preview dummies) | the element holds `EFFECT_GODMODE`, whose row implies all three |
| lite godmode | the element holds all three while attached |
| `BF_DISABLE_DURATION` 0 (modifiers) | unchanged: it scales increases to nothing |

Why: a flag has one owner. Godmode cleared the three flags on attach and set all three on
detach, so ending godmode on an AI gave it back a `CANWEAKEN` it never had, and two sources
(godmode and a mutation) could not both hold an immunity: whichever ended first ended it for
both. A hold is per source, is released only by that source, and dies with it, which is the
contribution store's rule for every other override (object_model_core.md §8). It also makes
immunity visible to the same readers as everything else (`om_value_of()`, diagnostics), and the
"gaining it ends the status" rule lives in one place instead of at every flag write. The other
`status_flags` (`CANPUSH`, `LEAPING`, `HIDING`, `PASSEMOTES`, `FAKEDEATH`) are not status
immunities and stay flags. Godmode is an effect too: code asks `om_has(mob, EFFECT_GODMODE)`.

## 8. Stasis and cryo: the biology clock

Stasis sources were `/datum/modifier/stasis/*` contributing `BF_STASIS`
(0..1), read once per `Life()` by `body.advance_stasis()`, which kept a
fractional counter and paused a cycle unless the counter filled.

Now each stasis modifier, while applied, **holds `EFFECT_CLOCK_BIO_INHIBIT`
= its depth on the mob, with the modifier as source**. The hold dies with the
modifier. The biology clock's rate is `1 - deepest stasis`.
`body.advance_stasis()` reads the mob's `CLOCK_BIO` rate once per frame and
adds it to a fractional counter; a frame runs biology only when the counter
fills. That is the old counter with its input now coming from the clock, so
stasis 0.9 still runs biology on one frame in ten, and a frame run by hand
(tests, admin effects) behaves like a scheduled one. Total stasis
(cryopods, cages) is rate 0: no biology step ever. `BF_STASIS` stays as a
factor for diagnosis readouts.

The frame itself is **not** on `CLOCK_BIO`: a mob in a stasis bag still runs
its HUD, statuses, AFK and client stages. Only the biology stages read the
paused flag (`ctx.fact("in_stasis")`, `inStasisNow()`), and the human tail's live and dead
stages are skipped for it (`LIFE_RUN_IF_LIVE_BIOLOGY`).

## 9. Suspension and transformation

- `mob.enabled = FALSE` (absorbed prey, the TF holder's body) removed the mob
  from Life entirely. It is now `om_suspend(mob, source)`: a suspension hold,
  off every ring, released by `om_unsuspend()` or by the source's deletion.
  The var is deleted.
- `transforming` is a fact (`placed` fails while transforming). It is not a suspension: the
  old code kept running the stages before the living core (upkeep, traits, instability), and
  the Codex prototype's "transformation halts all upkeep" was a bug. The human and alien
  pre stages still abort the whole frame while transforming, as their old early returns did.

## 10. Every living type

| Type | Life set | Notes |
|---|---|---|
| humans | `LIFE_SET_LIVING` | the full plan; `hud_refresh` is presentation; the live and dead tails read the biology clock |
| carbon, aliens, brains | `LIFE_SET_LIVING` | brains are `low_priority` |
| simple mobs (incl. slimes, borers, bots' simple kin) | `LIFE_SET_LIVING` | the simple tail runs while `alive`; most park within two frames |
| bots | `LIFE_SET_LIVING` | `bot_core` stays per cycle |
| robots, drones | `LIFE_SET_ROBOT` | their own families; `robot_interface` stays per cycle (it reads power) |
| AI | `LIFE_SET_AI` | own families; HUD and vision are presentation |
| pAI | `LIFE_SET_PAI` | own families |
| decoys | `LIFE_SET_DECOY` | |
| dummies, announcers | `LIFE_SET_DELIST` | |
| observers, AI eyes, blob overmind | none (not living) | `observer_upkeep` behaviour on `/mob/observer`, every `LIFE_CYCLE` (their old effective rate too) |

Lobby (`new_player`) and other non-living mobs ran only the base `/mob/Life()`
(followers, spell buttons), which does nothing for them; they get no pipeline.

## 11. Relevance

A low-priority mob (humans and simple mobs by default) runs Life only while its z-level has a
living player. That used to be a test at the start of every frame; now it is relevance:

- The `life` pipeline's `relevance` is `list(OM_PARK, null, null, null)`: at RELEVANCE_NONE the
  mob is off the ring, and nothing runs or is tested for it.
- A mob that isn't low priority holds RELEVANCE_NEAR on itself.
- Each z-level has a presence (`/datum/life_z_presence`) listing its low-priority mobs; while a
  living player is on that z-level the presence holds RELEVANCE_NEAR on each of them.
- `update_client_z()` (players arriving and leaving), `onTransitZ()` and `set_low_priority()`
  keep this current. Wakes still arrive while a mob is irrelevant, so it is up to date when it
  becomes relevant.

## 12. The Codex prototype's bugs, and why they can't happen

| Bug | Here |
|---|---|
| Dropped cadence slots on skipped ticks | the core ring never skips a slot; the step accumulator carries real elapsed time |
| Life starving timers | deadlines run first each pass with a guaranteed budget share |
| Wake deadlines running whole frames on awake mobs | wakes and rewakes only clear idle bits; frames only come from the ring |
| Fixed-step systems silently sped up 2.5-3.5x | the cycle is 6 s, chosen to keep per-second rates (§3) |
| Loose never-attached organs rotting | organ processing is untouched (SSobj); no decay behaviour attaches to organs |
| Timer wake passing the whole nap as seconds | unparking gives at most one interval (§5) |
| Transformation halting all upkeep | `transforming` is a fact; only `enabled` became a suspension (§9) |
| Benchmark reading `SSmobs.cost` after Life moved | the benchmark reads the `life` pipeline's cost from `om_diagnostics()` and its frame counter |
| Sampling bias in the profiler | the stage profiler samples every Nth *frame* by a scheduler-wide counter, not every Nth mob of a run list that restarts |

## 13. Tests

`code/modules/unit_tests/dq_life_om_tests.dm` (Life, mostly on a test scheduler with real mobs)
and `code/modules/unit_tests/dq_om_pipeline_tests.dm` (the runner on test entities, and the
machines):

| Area | Test |
|---|---|
| content | variants mirror mob paths; the human plan is in the legacy order; plans are shared per type; a robot's plan is the robot set; variant resolution for simple mobs |
| facts | a dead human skips its alive-only stages and they idle; a transforming human aborts the frame and idles nothing; a transforming mouse still runs its trait stages |
| cadence and catch-up | one frame per `LIFE_CYCLE` with one cycle of dt; a 20-cycle jump runs at most 2 frames, counted as breaches |
| parking | an idle mouse parks (listed, no missed wake), runs no frames, `injure()` unparks it whole, its next frame covers one cycle; hysteresis |
| wakes | an idle stage wakes only on its channels; a change raised during a frame wakes a later stage; login and stat wake everything |
| rewakes | a rewake unparks partially (one stage, one idle frame counted); a rewake runs no frame |
| deletion, death, suspension, relevance, stasis | as in §4, §8, §9, §11 |
| statuses | durations, set and adjust, expiry by deadline with no frame, rates (hallucination, dizziness resting), immunity (held, gained, mutation, godmode, multi-type decl), veto signal, voluntary sleep (no hidden floor), one raise per start and end, no self-wake |
| derive and present | canmove derived on a status change with no frame; presentation not started without a client |
| profiler, audit | uniform sampling by frame; the audit finds a missed wake, counts it and wakes the mob |
| runner (test entities) | after/before ordering, run_if over facts and checks, fact caching, idle/park/unpark and hysteresis, rewakes, abort scopes, catch-up, variants by depth, nested frames, multi-type decls, `min_interval` on behaviours and stages, runlevels |
| machines | a recharger charges, idles and parks, and wakes on insertion and power; APCs and SMES park, an APC failure ends by rewake |

## 14. Costs and limits

- One ring entry per awake, relevant living mob; parked and irrelevant mobs cost nothing per
  tick.
- A frame is one ring dispatch, then one bit test per stage and one call per awake stage (plus
  its `idle()`). Frames come from a pool; nothing is allocated unless a stage idles.
- Running statuses cost nothing per frame; each start and end is one deadline and one change.
- A wake is one queued `on_wake` per mob per pass, whatever the number of changes.
- `max_catchup = 2` means a scheduler stall longer than two cycles drops frames for per-cycle
  content, as the old scheduler did implicitly.
- Profiling: every 16th pipeline frame is timed per stage and mob type; `-DOM_NO_STAGE_PROFILE`
  compiles it out (benchmarks do).
