# Mob Life on the object-model core

Status: **design, implemented on `rewrite/life-om`**. Builds on
[object_model_core.md](object_model_core.md) (the API) and replaces the
scheduling half of [../mob_life_architecture.md](../mob_life_architecture.md)
§4.3 and §4.8-4.9. The content half stays: life systems, families and
variants, compositions, gates and segments are how Life *content* is
organised, and none of that changes here. What changes is everything that
decides **when** that content runs.

Benchmark results: [life_on_om_benchmark.md](life_on_om_benchmark.md).

## 1. What is replaced

| Old (deleted) | New |
|---|---|
| `SSmobs.fire()` walking `GLOB.mob_list` in 8 shrinking slices | the `life` behaviour's cadence ring |
| `/mob/living/Life(seconds, profile)` | `/mob/living/proc/life_frame()`, called by the ring (`on_step`) |
| `life_awake` bits, `LIFE_SYS_*`, `LIFE_WAKE_*` groups | per-system `wake_on` masks of mob change channels (`CHANGE_MOB_*`) |
| `life_wake(bits, reason)` in producers | `om_changed(L, CHANGE_MOB_*)` |
| `life_hibernate()`, `SSmobs.hibernating_mobs`, `life_hibernating` checks in SSmobs | `om_sleep(L, life)` (roster removal) and `om_resume()` |
| `life_wake_in()` and its `addtimer` | one `om_after()` deadline on the `life` behaviour, earliest due wins |
| `life_last_time` and `seconds` | the ring's dt; content per cycle runs as fixed steps |
| `period` (every Nth cycle) | unused; deleted |
| `body.advance_stasis()` fractional counter over `BF_STASIS` | `CLOCK_BIO` local time; stasis sources hold `EFFECT_CLOCK_BIO_INHIBIT` |
| `mob.enabled` (absorbed prey, TF holder) | `om_suspend(mob, source)` |
| `stunned`, `weakened`, `paralysis` counters | timed contributions `EFFECT_STUNNED`, `EFFECT_WEAKENED`, `EFFECT_PARALYZED` |
| per-mob `Life()` on observers, AI eyes, blob overmind via SSmobs | `observer_upkeep` behaviour on `/mob/observer` |
| MOB_PROFILE sampling on SSmobs | per-behaviour cost from `om_diagnostics()`, plus a uniform per-system sampler |

SSmobs remains only as the home of death reporting (`report_death()`,
`death_list`), the two-minute profile and hibernation summaries and the
missed-wake audit. It runs no Life.

## 2. The frame is one behaviour

`/datum/om/behaviour/life` is attached to every `/mob/living` by
`/datum/om/decl/living`. Its `on_step()` runs `life_frame()`: the mob's
composition in (phase, order), with the same `life_context`, gates, segments,
`LIFE_HALT` and legacy return values as before.

Why one behaviour and not one per family:

- **Order and gates.** Gates block segments for the rest of *one mob's*
  frame, and variants re-home systems between phases (`type_post` runs in
  `LIFE_PHASE_TAIL`, a variant can change its order). Separate behaviours
  run ring by ring: every entity in a slot runs behaviour A, then every
  entity runs behaviour B. The `life_context` would have to live on the mob
  between rings, and a budget deferral between A and B would split a frame
  across ticks.
- **Cost.** A human composes about 50 systems. Fifty ring entries per mob
  means fifty dispatches where there was one call, and the benchmark
  compares against a loop that makes one call.
- **Content is not rewritten.** The families and 571 variant types stay
  exactly as they are.

Three small behaviours sit next to it (§6): `life_derive` (status
derivation), `life_present` (HUD and vision, clients only) and
`observer_upkeep`.

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
  `Stun(2)` lasts 12 s as it did at a typical population.
- Anything that wants a different rate retunes one number. A later balance
  pass can move content to dt and shorten the cycle; this change does not
  mix a balance pass into a scheduler migration.

Tests and benchmarks may compile a different cycle (`-DLIFE_CYCLE_DS=20`);
the benchmark uses 2 s on both sides so both schedulers deliver the same
number of frames (§11, and the benchmark doc).

## 4. Per-frame semantics

`life_frame()`:

1. Build a `life_context` (`seconds = LIFE_CYCLE_SECONDS`).
2. Stasis: advance the biology clock (§8); `ctx.stasis` is TRUE when no
   biology step fell in this frame.
3. Run the composition in order. Skip a system that is asleep (§5), that is
   `wake_only` (§6), or whose segment a gate blocked. A system's tick may
   return `LIFE_HALT` (stop the frame) or `LIFE_SLEEP` (sleep now).
4. **Stop at once if the mob was deleted by a system.** The old loop kept
   running the remaining systems on a deleted mob.
5. After each system that ran, if its `idle()` holds, it goes to sleep;
   its `rewake_delay()` (if any) becomes a timer (§5).
6. After the frame, if every system but the gates is asleep, the mob
   hibernates.

Early-outs that are not sleeps: not in a game runlevel (the old SSmobs never
ran in the lobby), and `low_priority` mobs on a z-level with no living
player (the old `process_z` rule). These return before step 1 and cost one
proc call.

## 5. Sleep, wake, hibernation and timers

**State.** `life_asleep` is a lazy list parallel to the composition
(`TRUE` = asleep). Null means all awake, which is the common case for busy
mobs. There are no wake bits.

**What wakes a system.** Each system declares `wake_on`, a mask of mob
change channels. Producers raise channels with `om_changed()`:

| Channel | Raised by (was) |
|---|---|
| `CHANGE_MOB_HEALTH` | `injure()`, `mend()`, `fully_heal()`, `body.invalidate()` (was `LIFE_WAKE_BODY`) |
| `CHANGE_MOB_STATUS` | status setters, the status effects' changes (was `LIFE_WAKE_STATUS`) |
| `CHANGE_MOB_LOC` | `/mob/living/Moved()` (was `LIFE_WAKE_MOVED`) |
| `CHANGE_MOB_EQUIPMENT` | equip and unequip (was `LIFE_WAKE_EQUIPMENT`) |
| `CHANGE_MOB_CONDITIONS` (new, bit 18) | modifiers, instability, diseases (was `LIFE_SYS_UPKEEP`) |
| `CHANGE_MOB_STAT` | `set_stat()` (was "wake all") |
| `CHANGE_MOB_CLIENT` | Login, Logout (was "wake all") |
| `CHANGE_EXPLICIT` | `om_wake()`, recomposition, the audit |

`STAT`, `CLIENT` and `EXPLICIT` wake every system, as the old "all" wakes
did. Each old wake bit maps to the union of the channels whose group
contained it; the table is `LIFE_WAKE_ON_*` in `life_systems.dm` and is a
mechanical translation, so a system wakes on exactly what woke it before.

**How a wake arrives.** The `life` behaviour's `wake_on` is the union of all
of those channels, so `om_changed()` queues one `on_wake(mob, changes)` per
pass with the union of bits. `on_wake` clears the asleep flag of each
system whose `wake_on` matches. It never runs a frame: a woken system runs
in the mob's next frame. (The old `life_wake()` set bits and let the next
`Life()` run them; same thing.) A change raised *during* a frame is
delivered after the frame, so a system put to sleep at the end of the frame
is woken right back, which is what the old `life_cycle_wakes` did by hand.

**Hibernation** is roster removal: `om_sleep(mob, life)` takes the mob off
the ring. Wakes and deadlines still arrive. The first wake of a hibernating
mob wakes *every* system (as before, so each re-checks its rule) and calls
`om_resume()`. The frame's first step after resuming covers at most one
interval of time: the ring gives a newly joined entity at most one interval
of dt, and the step accumulator carries at most the fraction it had. **A
nap is never passed as elapsed time.**

**Timers.** `rewake_delay()` returns deciseconds after which an idle system
wakes anyway (darksight, AFK, ambience, air drifting in place). The mob keeps
`life_timers` (system -> due); the `life` behaviour holds one deadline
(`om_after()`) at the earliest due. `on_deadline` wakes the due systems,
resuming the mob if it hibernates, and re-arms for the next due. **It never
runs a frame on an awake mob**: the woken system waits for the next frame.

**Audit.** Unchanged in purpose: in test and TESTING builds every 30 s,
SSmobs samples hibernating mobs (from `GLOB.life_hibernating_mobs`, written
only by the two procs that sleep and resume) and awake mobs with sleeping
systems, and asks every sleeping system's `idle()`. A rule that no longer
holds is a missed `om_changed()`: logged, the test failed, the mob woken.

## 6. Wake-only systems

Some systems only derive presentation or state from other state. They should
run when that state changes, not on a 6 s cadence, and not at all for mobs
nobody watches.

- `wake_only = LIFE_WAKE_ONLY_DERIVE`: `canmove`. Run by `life_derive`
  (`wake_on = CHANGE_MOB_STATUS | CHANGE_MOB_STAT`, lane `LANE_DERIVED`) the
  pass the status changes. Stun, weaken and paralysis changes now update
  `canmove` and lying immediately (they used to wait for the next cycle for
  paralysis).
- `wake_only = LIFE_WAKE_ONLY_PRESENT`: `hud`, `vision`, `hud_refresh`
  (human). Run by `life_present` (`requires` a client, lane
  `LANE_PRESENTATION`) on HUD channels, and by its own deadline for their
  `rewake_delay()` (darksight 5 s, HUD refresh 1 min). **Clientless mobs do
  not attach it at all**: no HUD or vision work for NPCs, which is the
  relevance saving. Login raises `CHANGE_MOB_CLIENT`, which re-checks the
  requirement, starts the behaviour and runs them once.

`refresh_hud()`, `refresh_vision()` and `run_life_system()` still run a
system on demand.

## 7. Statuses as contributions

`stunned`, `weakened` and `paralysis` were counters decremented once per
frame by the statuses system. They are now timed contributions in the
contribution store:

| Old | New |
|---|---|
| `Stun(n)` (never shortens) | `EFFECT_STUNNED` until `max(current, now + n * LIFE_CYCLE)` |
| `SetStunned(n)` | exactly `now + n * LIFE_CYCLE` (0 releases) |
| `AdjustStunned(n)` | `current + n * LIFE_CYCLE`, clamped at now |
| `M.stunned` (read) | `M.get_stunned()`: remaining, in old units (ceil) |
| `if(M.stunned)` | `M.is_stunned()` |
| statuses system decrementing | the deadline wheel expires it; nothing ticks |

Same for weaken (`EFFECT_WEAKENED`, new) and paralysis (`EFFECT_PARALYZED`).
The mob itself is the source (`key = "status"`), so the setters keep their
exact old semantics. The three effects use a custom effect type whose
`on_changed` updates `canmove`, lying and the alert, and raises
`CHANGE_MOB_STATUS`. `EFFECT_CAN_MOVE` and `EFFECT_CAN_ACT` (library
composites) now have real inputs.

Intentional differences, all small:
- A status now expires at its exact time rather than at the next frame
  boundary (up to one cycle sooner).
- It counts down while the mob is dead or transforming (the old status
  segment was blocked then, freezing the counter). A dead mob's stun is
  meaningless; a transforming mob's stun used to resume afterwards.
- Alerts and `canmove` update the moment the status changes.

`sleeping`, `confused`, `eye_blind`, `stuttering`, `silent`, `druggy` and
`slurring` stay counters for now: each has per-cycle side effects (waking
speed per species, dreams, eye healing, speech mangling) that belong to their
systems. They keep waking the statuses system through `CHANGE_MOB_STATUS`.

## 8. Stasis and cryo: the biology clock

Stasis sources were `/datum/modifier/stasis/*` contributing `BF_STASIS`
(0..1), read once per `Life()` by `body.advance_stasis()`, which kept a
fractional counter and paused a cycle unless the counter filled.

Now each stasis modifier, while applied, **holds `EFFECT_CLOCK_BIO_INHIBIT`
= its depth on the mob, with the modifier as source**. The hold dies with the
modifier. The biology clock's rate is `1 - deepest stasis`.
`body.advance_stasis()` reads the mob's `CLOCK_BIO` local time: a frame runs
biology only if a full `LIFE_CYCLE` of biological time has accumulated since
the last biology step. That is the old fractional counter, expressed as a
clock, so stasis 0.9 still runs biology on one frame in ten. Total stasis
(cryopods, cages) is rate 0: no biology step ever. `BF_STASIS` stays as a
factor for diagnosis readouts.

The frame itself is **not** on `CLOCK_BIO`: a mob in a stasis bag still runs
its HUD, statuses, AFK and client systems. Only the biology systems read the
paused flag, exactly as before (`ctx.in_stasis()`, `inStasisNow()`).

## 9. Suspension and transformation

- `mob.enabled = FALSE` (absorbed prey, the TF holder's body) removed the mob
  from Life entirely. It is now `om_suspend(mob, source)`: a suspension hold,
  off every ring, released by `om_unsuspend()` or by the source's deletion.
  The var is deleted.
- `transforming` stays a gate (`gate/transforming` blocks `LIFE_SEG_LIVING`).
  It is not a suspension: the old code kept running the systems outside that
  segment (upkeep, traits, instability), and the Codex prototype's
  "transformation halts all upkeep" was a bug.

## 10. Every living type

| Type | Life set | Notes |
|---|---|---|
| humans | `LIFE_SET_LIVING` | full composition; `hud_refresh` is wake-only; human vitals gate reads the biology clock |
| carbon, aliens, brains | `LIFE_SET_LIVING` | brains are `low_priority` |
| simple mobs (incl. slimes, borers, bots' simple kin) | `LIFE_SET_LIVING` | `simple_vitals` gate; most hibernate within two frames |
| bots | `LIFE_SET_LIVING` | `bot_core` stays per cycle |
| robots, drones | `LIFE_SET_ROBOT` | their own families; `robot_interface` stays per cycle (it reads power) |
| AI | `LIFE_SET_AI` | own families; HUD and vision wake-only |
| pAI | `LIFE_SET_PAI` | own families |
| decoys | `LIFE_SET_DECOY` | |
| dummies, announcers | `LIFE_SET_DELIST` | |
| observers, AI eyes, blob overmind | none (not living) | `observer_upkeep` behaviour on `/mob/observer`, every `LIFE_CYCLE` (their old effective rate too) |

Lobby (`new_player`) and other non-living mobs ran only the base `/mob/Life()`
(followers, spell buttons), which does nothing for them; they get no behaviour.

## 11. Relevance

- Clientless mobs don't attach `life_present` (§6).
- `low_priority` mobs skip frames on player-free z-levels (§4).
- Nothing else uses relevance levels yet. A later step can give the frame a
  `relevance` list (slower frames for mobs no player can see); that is a
  balance change and is not part of this migration.

## 12. The Codex prototype's bugs, and why they can't happen

| Bug | Here |
|---|---|
| Dropped cadence slots on skipped ticks | the core ring never skips a slot; the step accumulator carries real elapsed time |
| Life starving timers | deadlines run first each pass with a guaranteed budget share |
| Wake deadlines running whole frames on awake mobs | `on_deadline` and `on_wake` only clear asleep flags; frames only come from the ring |
| Fixed-step systems silently sped up 2.5-3.5x | the cycle is 6 s, chosen to keep per-second rates (§3) |
| Loose never-attached organs rotting | organ processing is untouched (SSobj); no decay behaviour attaches to organs |
| Timer wake passing the whole nap as seconds | resuming gives at most one interval (§5) |
| Transformation halting all upkeep | `transforming` stays a gate; only `enabled` became a suspension (§9) |
| Benchmark reading `SSmobs.cost` after Life moved | the benchmark reads the `life` behaviour's cost from `om_diagnostics()` and counts frames itself |
| Sampling bias in the profiler | the per-system sampler samples every Nth *frame* by a global counter, not every Nth mob of a run list that restarts |

## 13. Parity test plan

Tests live in `code/modules/unit_tests/dq_life_om_tests.dm`, most on a test
scheduler (`om_test_begin()`, `scheduler_advance()`), with real mobs.

| Area | Test |
|---|---|
| cadence and dt | a mob runs one frame per `LIFE_CYCLE` over 10 cycles, `ctx.seconds == LIFE_CYCLE_SECONDS`; physiology integrates the same dt total |
| skipped ticks | `sched.jump()` of 3 cycles: exactly `max_catchup` frames, the rest counted as breaches, no double frames |
| catch-up bound | a 20-cycle jump never runs more than 2 frames in one pass |
| hibernation | an idle mouse hibernates (off the ring), `injure()` wakes it whole, its next frame's dt is at most one cycle |
| per-system sleep | a system sleeps after an idle tick and wakes only on its channels |
| timers | a system with `rewake_delay()` wakes by deadline; an awake mob's deadline doesn't run a frame |
| wakes during a frame | a change raised by a system during the frame keeps a later system awake |
| death and revive | `set_stat(DEAD)` wakes all; dead segments block; revive resumes the live segments |
| deletion mid-frame | a system that qdels the mob stops the frame; nothing runs on a deleted mob; its deadlines are skipped |
| transformation | `transforming` blocks the living segment but upkeep still runs; nothing sleeps that frame |
| suspension | absorbed prey (`om_suspend`) runs no frame; releasing resumes it |
| stasis | stasis 0.9 runs biology on 1 frame in 10 via the clock; total stasis never; HUD systems still run |
| statuses | `Stun(2)` lasts `2 * LIFE_CYCLE`; `SetStunned(0)` ends it; `AdjustStunned(-1)` shortens; `canmove` updates immediately |
| wake-only | a status change runs `canmove` without a frame; a clientless mob has no `life_present` |
| organs | a human's internal organs process once per frame, as before |
| observers | an observer's upkeep runs on its own behaviour |
| Codex bugs | one assertion per row of §12 |

The existing content tests that drove `Life()` by hand now call
`life_frame()`.

## 14. Costs and limits

- One ring entry per awake living mob; hibernating mobs cost nothing per tick.
- A wake is one queued `on_wake` per mob per pass, whatever the number of
  changes.
- The asleep list is allocated only while something sleeps.
- `max_catchup = 2` means a scheduler stall longer than two cycles drops
  frames for per-cycle content, as the old scheduler did implicitly.
- Profiling: `-DLIFE_NO_PROFILE` compiles the per-system sampler out
  (benchmarks do).
